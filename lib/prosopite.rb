require 'fileutils'
require 'set'
require 'yaml'
require 'prosopite/version'
require 'prosopite/fixes'

module Prosopite
  DEFAULT_ALLOW_LIST = [
    /active_record\/relation.rb.*preload_associations/,
    'active_record/validations/uniqueness'
  ].freeze

  # Ruby 3.2+ can pass values on to the fibers spawned by the current one
  FIBER_STORAGE = Fiber.respond_to?(:[])

  # The call stacks of queries that ran once, kept to show where records were loaded, take
  # memory, so only this many are kept per scan
  MAX_SINGLE_CALLERS = 500

  TODO_HEADER = <<~YAML
    # Known N+1 queries, which Prosopite ignores until they're fixed. Remove the entries of
    # the ones you fix, or delete this file and record it again with Prosopite.record_todo.
  YAML

  class NPlusOneQueriesError < StandardError; end

  # An Active Support subscriber that pauses scans during its event, see Prosopite.pause_during
  class EventPause
    def start(_name, _id, _payload)
      (Thread.current[:prosopite_event_pauses] ||= []) << Prosopite.send(:begin_pause)
    end

    def finish(_name, _id, _payload)
      Prosopite.send(:end_pause, Thread.current[:prosopite_event_pauses].pop)
    end
  end
  class << self
    attr_writer :raise,
                :stderr_logger,
                :rails_logger,
                :prosopite_logger,
                :custom_logger,
                :ignore_pauses,
                :backtrace_cleaner,
                :enabled,
                :suggest_fixes

    attr_accessor :allow_stack_paths,
                  :focus_stack_paths,
                  :ignore_queries,
                  :min_n_queries,
                  :display_max_n_queries,
                  :display_query_count,
                  :add_footer,
                  :browser_console,
                  :record_todo,
                  :github_annotations,
                  :json_report,
                  :min_duration_ms

    attr_reader :todo_file

    attr_reader :ignore_location_paths

    def ignore_location_paths=(paths)
      @ignore_location_paths = paths
      # One regexp for all, as String#match? would compile one for every frame of every query
      @ignore_location_paths_regexp = paths.blank? ? nil : patterns_regexp(paths)
      # The frames of a file have the same path string in every query, so match it once
      @ignored_paths = {}.compare_by_identity
    end

    def allow_list=(value)
      warn "Prosopite.allow_list= is deprecated and will be removed in 3.0. Use Prosopite.allow_stack_paths= instead."

      self.allow_stack_paths = value
    end

    attr_reader :sample_rate

    def sample_rate=(rate)
      share = rate.nil? ? nil : Float(rate)
      raise ArgumentError, "Prosopite.sample_rate must be from 0 to 1, not #{rate}" unless share.nil? || share.between?(0, 1)

      @sample_rate = share
    end

    def todo_file=(path)
      @todo_file = path&.to_s
      @todo_entries = nil
      @todo_recorded = Set.new
    end

    def backtrace_cleaner
      @backtrace_cleaner ||= Rails.backtrace_cleaner
    end

    def enabled?
      @enabled != false
    end

    def disabled?
      !enabled?
    end

    def suggest_fixes?
      @suggest_fixes != false
    end

    def scan(context = nil)
      # A scan of the current fiber, even a paused one, makes this one nested, while a
      # fiber spawned during a scan can still start a scan of its own
      own_state = Thread.current[:prosopite_state]
      if (own_state && own_state[:prosopite_scan]) || disabled? || (@sample_rate && rand >= @sample_rate)
        return block_given? ? yield : nil
      end

      state = start_scan(context)

      if block_given?
        begin
          block_result = yield
          finish
          block_result
        ensure
          discard(state)
        end
      end
    end

    # Runs the block in a scan of its own and returns its N+1 queries, without sending
    # them anywhere or raising, e.g. for test assertions
    def n_plus_one_queries
      outer_state = Thread.current[:prosopite_state]
      outer_inherited_state = Fiber[:prosopite_state] if FIBER_STORAGE
      outer_notifications = tc[:prosopite_notifications]
      state = start_scan(nil)
      # The scans of code in the block, e.g. of the Rack middleware, can't finish it
      state[:prosopite_assertion] = true

      begin
        yield
        state[:prosopite_scan] = false
        create_notifications
        build_notifications
      ensure
        release(state)
        Thread.current[:prosopite_state] = outer_state
        Fiber[:prosopite_state] = outer_inherited_state if FIBER_STORAGE
        tc[:prosopite_notifications] = outer_notifications
      end
    end

    def tc
      Thread.current
    end

    # A pause applies to the whole scan, in every fiber and thread taking part in it
    def pause
      if @ignore_pauses
        return block_given? ? yield : nil
      end

      if block_given?
        state = begin_pause
        begin
          yield
        ensure
          end_pause(state)
        end
      elsif (state = scan_state)
        state[:prosopite_paused] = true
      end
    end

    # Pauses scans while the code instrumented as this Active Support event runs,
    # e.g. 'factory_bot.run_factory' for the factories of FactoryBot
    def pause_during(event)
      ActiveSupport::Notifications.subscribe(event, EventPause.new)
    end

    def resume
      state = scan_state
      state[:prosopite_paused] = false if state
    end

    def scan?
      !!scanning_state
    end

    def finish
      # Only the fiber that started the scan, or the thread of an ActionController::Live
      # action, can finish it, even while it's paused, e.g. by another fiber or thread
      state = Thread.current[:prosopite_state]
      return unless state && state[:prosopite_scan] && !state[:prosopite_assertion]

      state[:prosopite_scan] = false

      begin
        create_notifications
        filter_notifications
        tc[:prosopite_notifications].present? ? send_notifications : []
      ensure
        discard(state)
      end
    end

    def start_raise
      tc[:prosopite_local_raise] = true
    end

    def stop_raise
      tc[:prosopite_local_raise] = false
    end

    def local_raise?
      tc[:prosopite_local_raise] == true
    end

    def raise?
      local_raise? || !!@raise
    end

    def create_notifications
      state = Thread.current[:prosopite_state]
      # By identity, as the queries of N+1s in different places can be the same strings
      tc[:prosopite_notifications] = {}.compare_by_identity
      allow_list = nil
      # The queries of an N+1 are often the same string, with bind parameters
      fingerprints_by_adapter = Hash.new do |by_adapter, adapter|
        by_adapter[adapter] = Hash.new { |by_query, query| by_query[query] = fingerprint_query(query, adapter) }
      end

      # A copy, as an ActionController::Live action may still be running queries
      state[:prosopite_query_counter].dup.each do |location_key, count|
        if count >= @min_n_queries
          db_adapter = state[:prosopite_query_adapter][location_key]
          fingerprints = state[:prosopite_query_holder][location_key].group_by do |q|
            begin
              fingerprints_by_adapter[db_adapter][q]
            rescue
              raise q
            end
          end

          queries = fingerprints.select { |_, q| q.size >= @min_n_queries }

          next unless queries.any?

          kaller = state[:prosopite_query_caller][location_key].map(&:to_s)
          allow_list ||= patterns_regexp(@allow_stack_paths + DEFAULT_ALLOW_LIST)
          is_allowed = kaller.any? { |f| f.match?(allow_list) }
          is_focused = @focus_stack_paths.empty? ||
                       kaller.any? { |f| @focus_stack_paths.any? { |s| s.is_a?(Regexp) ? f.match?(s) : f.include?(s) } }

          if is_focused && !is_allowed
            duration_ms = state[:prosopite_query_duration][location_key]
            queries.each do |fingerprint, q|
              tc[:prosopite_notifications][q] = {
                kaller: kaller, duration_ms: duration_ms, fingerprint: fingerprint, location_key: location_key
              }
            end
          end
        end
      end
    end

    def fingerprint(query, db_adapter = ActiveRecord::Base.connection_db_config.adapter)
      if db_adapter.match?(/mysql|trilogy/i)
        mysql_fingerprint(query)
      elsif db_adapter.match?(/postg/i) && pg_query?
        PgQuery.fingerprint(query)
      else
        # SQLite, Oracle, PostgreSQL without pg_query etc. use double quotes for identifiers, not strings
        mysql_fingerprint(query, ansi_quotes: true)
      end
    end

    # Many thanks to https://github.com/genkami/fluent-plugin-query-fingerprint/
    def mysql_fingerprint(query, ansi_quotes: false)
      query = query.dup

      return "mysqldump" if query =~ %r#\ASELECT /\*!40001 SQL_NO_CACHE \*/ \* FROM `#
      return "percona-toolkit" if query =~ %r#\*\w+\.\w+:[0-9]/[0-9]\*/#
      if match = /\A\s*(call\s+\S+)\(/i.match(query)
        return match.captures.first.downcase!
      end

      if match = /\A((?:INSERT|REPLACE)(?: IGNORE)?\s+INTO.+?VALUES\s*\(.*?\))\s*,\s*\(/im.match(query)
        query = match.captures.first
      end

      query.gsub!(%r#/\*[^!].*?\*/#m, "")
      query.gsub!(/(?:--|#)[^\r\n]*(?=[\r\n]|\Z)/, "")

      return query if query.gsub!(/\Ause \S+\Z/i, "use ?")

      query.gsub!(/\\["']/, "")
      query.gsub!(/".*?"/m, "?") unless ansi_quotes
      query.gsub!(/'.*?'/m, "?")
      # The placeholders of PostgreSQL, before the numbers, so that IN lists of them collapse
      query.gsub!(/\$\d+/, "?") if ansi_quotes

      query.gsub!(/\btrue\b|\bfalse\b/i, "?")

      query.gsub!(/[0-9+-][0-9a-f.x+-]*/, "?")
      query.gsub!(/[xb.+-]\?/, "?")

      query.strip!
      query.gsub!(/[ \n\t\r\f]+/, " ")
      query.downcase!

      query.gsub!(/\bnull\b/i, "?")

      query.gsub!(/\b(in|values?)(?:[\s,]*\([\s?,]*\))+/, "\\1(?+)")

      query.gsub!(/(?<!\w)field\s*\(\s*(\S+)\s*,\s*(\?+)(?:\s*,\s*\?+)*\)/, 'field(\1, \2+)')

      query.gsub!(/\b(select\s.*?)(?:(\sunion(?:\sall)?)\s\1)+/, "\\1 /*repeat\\2*/")

      query.gsub!(/\blimit \?(?:, ?\?| offset \?)/, "limit ?")

      if query =~ /\border by/
        query.gsub!(/\G(.+?)\s+asc/, "\\1")
      end

      query
    end

    def send_notifications
      notifications = build_notifications

      notifications.each do |notification|
        ActiveSupport::Notifications.instrument('n_plus_one_queries.prosopite', notification)
      end

      notifications_str = notifications.map { |notification| notification_message(notification) }.join

      annotate_github(notifications) if @github_annotations
      write_json_report(notifications) if @json_report

      @custom_logger.warn(notifications_str) if @custom_logger

      Rails.logger&.warn(red(notifications_str)) if rails_logger?
      $stderr.puts(red(notifications_str)) if @stderr_logger
      log_to_file(notifications_str) if @prosopite_logger

      raise NPlusOneQueriesError.new(notifications_str) if raise?

      notifications
    end

    def notification_message(notification)
      queries = notification[:queries]
      duration_ms = notification[:duration_ms]

      details = []
      details << "#{queries.count} queries" if @display_query_count
      details << "#{duration_ms.round(1)}ms"

      message = String.new("N+1 queries detected (#{details.join(', ')}):\n")

      queries_to_display =
        if @display_max_n_queries
          queries.take(@display_max_n_queries)
        else
          queries
        end

      queries_to_display.each { |q| message << "  #{q}\n" }

      if notification[:fixes].present?
        message << (notification[:fixes].size == 1 ? "Possible fix:\n" : "Possible fixes:\n")
        notification[:fixes].each do |fix|
          message << "  #{fix}\n"
        end
      end

      if notification[:context]
        message << "Context:\n"
        notification[:context].to_s.each_line do |line|
          message << "  #{line.chomp}\n"
        end
      end

      # Last, as extensions like dial read the frames after it
      message << "Call stack:\n"
      notification[:call_stack].each do |f|
        message << "  #{f}\n"
      end

      message << "\n"
    end

    # Unless it's set, the Rails log is where N+1 queries go when no other logger is set
    def rails_logger?
      @rails_logger.nil? ? !(@custom_logger || @stderr_logger || @prosopite_logger) : @rails_logger
    end

    def red(str)
      str.split("\n").map { |line| "\e[91m#{line}\e[0m" }.join("\n")
    end

    def ignore_query?(sql)
      return false if @ignore_queries.blank?

      @ignore_queries.any? { |q| q === sql }
    end

    def subscribe
      @subscribed ||= false
      return if @subscribed

      ActiveSupport::Notifications.subscribe 'sql.active_record' do |_, start, finish, _, data|
        sql, name = data[:sql], data[:name]
        state = scanning_state

        if state && name != "SCHEMA" && data[:cached].nil? && sql.include?('SELECT') && !ignore_query?(sql)
          query_caller = caller_locations
          connection = data[:connection]
          pool = connection&.pool
          ignore_regexp = @ignore_location_paths_regexp
          ignored_paths = @ignored_paths
          # Queries on different databases (e.g. shards) can't be merged into one,
          # so they are kept under different location keys.
          # Calculate the location key with as few allocations as possible
          location_key = [(pool.db_config if pool.respond_to?(:db_config))].tap do |array|
            query_caller.each do |loc|
              path = loc.path
              next if ignore_regexp && ignored_paths.fetch(path) { ignored_path!(ignored_paths, ignore_regexp, path) }

              array << path
              array << loc.lineno
            end
          end.hash

          counter = state[:prosopite_query_counter]
          state[:prosopite_query_holder][location_key] << sql
          state[:prosopite_query_duration][location_key] += (finish - start) * 1000
          state[:prosopite_query_adapter][location_key] ||= connection&.adapter_name

          # Store the call stack before the count reaches 2, since an ActionController::Live
          # action can still run queries while the request thread finishes the scan. Fix
          # suggestions show where records were loaded from the ones of single queries too.
          callers = state[:prosopite_query_caller]
          if counter[location_key] > 0 || callers.size < MAX_SINGLE_CALLERS
            callers[location_key] ||= query_caller
          end
          counter[location_key] += 1
        end
      end

      @subscribed = true
    end

    private

    # pg_query is optional, as its native extension can be hard to install
    def pg_query?
      return @pg_query if defined?(@pg_query)

      @pg_query =
        begin
          require 'pg_query'
          true
        rescue LoadError
          false
        end
    end

    # true for log/prosopite.log, or a path, or a logger
    def log_to_file(notifications_str)
      return @prosopite_logger.warn(notifications_str) if @prosopite_logger.respond_to?(:warn)

      path = @prosopite_logger == true ? File.join(Rails.root, 'log', 'prosopite.log') : @prosopite_logger.to_s
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, 'a') { |file| file.puts(notifications_str) }
    end

    def begin_pause
      return if @ignore_pauses

      state = scan_state
      state[:prosopite_pauses] += 1 if state
      state
    end

    def end_pause(state)
      state[:prosopite_pauses] -= 1 if state
    end

    def start_scan(context)
      subscribe

      @allow_stack_paths ||= []
      @focus_stack_paths ||= []
      @ignore_pauses ||= false
      @min_n_queries ||= 2

      # A new state for every scan, so that fibers or threads still holding the
      # previous one can't add to this scan
      state = {
        prosopite_scan: true,
        prosopite_paused: false,
        prosopite_pauses: 0,
        prosopite_query_counter: Hash.new(0),
        prosopite_query_holder: Hash.new { |h, k| h[k] = [] },
        prosopite_query_caller: {},
        prosopite_query_duration: Hash.new(0.0),
        prosopite_query_adapter: {},
        prosopite_context: context,
        thread: Thread.current
      }
      Thread.current[:prosopite_state] = state
      Fiber[:prosopite_state] = state if FIBER_STORAGE
      state
    end

    def build_notifications
      state = Thread.current[:prosopite_state]
      loads = Fixes::Loads.new(state, backtrace_cleaner) if suggest_fixes?
      tc[:prosopite_notifications].map do |queries, info|
        {
          queries: queries,
          call_stack: backtrace_cleaner.clean(info[:kaller]),
          duration_ms: info[:duration_ms],
          fixes: fixes(queries.first, info[:location_key], loads),
          fingerprint: info[:fingerprint],
          context: state[:prosopite_context]
        }
      end
    end

    # Computed for the N+1 queries left after the filters, as they take some time
    def fixes(query, location_key, loads)
      return [] unless loads && location_key

      Fixes.for(query, loop_table: loads.loop_table(location_key)) { |model| loads.at(location_key, model.table_name) }
    rescue StandardError
      # A suggestion must never keep an N+1 from being reported
      []
    end

    # The state of the scan of the current fiber: set by the fiber that started it,
    # copied by ActionController::Live to the thread of its action, and passed on
    # to the fibers spawned in the same thread
    def scan_state
      state = Thread.current[:prosopite_state]
      return state if state || !FIBER_STORAGE

      state = Fiber[:prosopite_state]
      state if state && state[:thread].equal?(Thread.current)
    end

    # Workflow commands that show the N+1 queries on the code in GitHub Actions, once each
    def annotate_github(notifications)
      @github_annotated ||= Set.new

      notifications.each do |notification|
        file, line = notification[:call_stack].first.to_s.match(/\A(.+?):(\d+)/)&.captures
        next unless @github_annotated.add?([file, line, notification[:fingerprint]])

        properties = { file: file, line: line, title: 'N+1 queries detected' }.compact
        properties = properties.map { |name, value| "#{name}=#{escape_github(value).gsub(':', '%3A').gsub(',', '%2C')}" }
        $stdout.puts("::warning #{properties.join(',')}::#{escape_github(notification_message(notification).chomp)}")
      end
    end

    def escape_github(value)
      value.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
    end

    # A line of JSON for each N+1, under a lock, as parallel test processes write together
    def write_json_report(notifications)
      File.open(@json_report, 'a') do |file|
        file.flock(File::LOCK_EX)
        notifications.each { |notification| file.puts(notification.to_json) }
      end
    end

    # Filters for the N+1 queries to report, which assertions don't use
    def filter_notifications
      if @min_duration_ms
        tc[:prosopite_notifications].reject! { |_, info| info[:duration_ms].to_f < @min_duration_ms }
      end
      apply_todo if @todo_file
    end

    # Ignores the N+1 queries in the todo file, or records them to it
    def apply_todo
      tc[:prosopite_notifications].reject! do |queries, info|
        entry = { 'fingerprint' => info[:fingerprint], 'location' => todo_location(info[:kaller]) }

        if @record_todo
          # Once per process, as each entry rewrites the file
          add_todo_entry(entry.merge('query' => queries.first)) if @todo_recorded.add?(entry.values)
          true
        else
          todo_entries.include?([entry['fingerprint'], entry['location']])
        end
      end
    end

    # The file of the N+1, without its line, so that unrelated changes don't affect it
    def todo_location(kaller)
      backtrace_cleaner.clean(kaller).first&.sub(/:\d+.*\z/, '')
    end

    def todo_entries
      @todo_entries ||= read_todo_entries(@todo_file).map { |entry| [entry['fingerprint'], entry['location']] }.to_set
    end

    def read_todo_entries(path)
      File.exist?(path) ? YAML.safe_load(File.read(path)) || [] : []
    end

    # Merges the entry into the file, under a lock, as parallel test processes record together
    def add_todo_entry(entry)
      File.open(@todo_file, File::RDWR | File::CREAT, 0o644) do |file|
        file.flock(File::LOCK_EX)
        entries = YAML.safe_load(file.read) || []
        next if entries.any? { |e| e.values_at('fingerprint', 'location') == entry.values_at('fingerprint', 'location') }

        entries << entry
        entries.sort_by! { |e| [e['location'].to_s, e['fingerprint'].to_s] }
        file.rewind
        file.write(TODO_HEADER + entries.to_yaml)
        file.truncate(file.pos)
      end
    end

    def scanning_state
      state = scan_state
      state if state && scanning?(state)
    end

    def scanning?(state)
      state[:prosopite_scan] && !state[:prosopite_paused] && state[:prosopite_pauses].zero?
    end

    def ignored_path!(ignored_paths, ignore_regexp, path)
      # Reloading in development makes new path strings
      ignored_paths.clear if ignored_paths.size >= 10_000
      ignored_paths[path] = ignore_regexp.match?(path)
    end

    # Strings are patterns too, like for String#match?
    def patterns_regexp(patterns)
      Regexp.union(patterns.map { |pattern| pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern) })
    end

    # Ends the scan of the state without reporting it
    def discard(state)
      state[:prosopite_scan] = false
      if Thread.current[:prosopite_state].equal?(state)
        Thread.current[:prosopite_state] = nil
        Fiber[:prosopite_state] = nil if FIBER_STORAGE
      end
      release(state)
    end

    # Extensions may override fingerprint(query) without the adapter, as before 2.3.0
    def fingerprint_query(query, db_adapter)
      if db_adapter && method(:fingerprint).arity != 1
        fingerprint(query, db_adapter)
      else
        fingerprint(query)
      end
    end

    # Fibers and threads that inherited the state, like threads created during
    # the scan, can keep it for their lifetime, so empty it
    def release(state)
      state[:thread] = nil
      state[:prosopite_context] = nil
      state[:prosopite_query_counter].clear
      state[:prosopite_query_holder].clear
      state[:prosopite_query_caller].clear
      state[:prosopite_query_duration].clear
      state[:prosopite_query_adapter].clear
    end
  end
end
