
module Prosopite
  DEFAULT_ALLOW_LIST = [
    /active_record\/relation.rb.*preload_associations/,
    'active_record/validations/uniqueness'
  ].freeze

  class NPlusOneQueriesError < StandardError; end
  class << self
    attr_writer :raise,
                :stderr_logger,
                :rails_logger,
                :prosopite_logger,
                :custom_logger,
                :ignore_pauses,
                :backtrace_cleaner,
                :enabled

    attr_accessor :allow_stack_paths,
                  :focus_stack_paths,
                  :ignore_queries,
                  :ignore_location_paths,
                  :min_n_queries,
                  :display_max_n_queries,
                  :display_query_count,
                  :add_footer,
                  :browser_console

    def allow_list=(value)
      puts "Prosopite.allow_list= is deprecated. Use Prosopite.allow_stack_paths= instead."

      self.allow_stack_paths = value
    end

    def backtrace_cleaner
      @backtrace_cleaner ||= Rails.backtrace_cleaner
    end

    def enabled?
      @enabled = true if @enabled.nil?

      @enabled
    end

    def disabled?
      !enabled?
    end

    def scan(context = nil)
      tc[:prosopite_scan] ||= false
      if scan? || disabled?
        return block_given? ? yield : nil
      end

      subscribe

      tc[:prosopite_query_counter] = Hash.new(0)
      tc[:prosopite_query_holder] = Hash.new { |h, k| h[k] = [] }
      tc[:prosopite_query_caller] = {}
      tc[:prosopite_query_duration] = Hash.new(0.0)
      tc[:prosopite_query_adapter] = {}
      tc[:prosopite_context] = context

      @allow_stack_paths ||= []
      @focus_stack_paths ||= []
      @ignore_pauses ||= false
      @min_n_queries ||= 2

      tc[:prosopite_scan] = true

      if block_given?
        begin
          block_result = yield
          finish
          block_result
        ensure
          tc[:prosopite_scan] = false
        end
      end
    end

    def tc
      Thread.current
    end

    def pause
      if @ignore_pauses
        return block_given? ? yield : nil
      end

      if block_given?
        begin
          previous = tc[:prosopite_scan]
          tc[:prosopite_scan] = false
          yield
        ensure
          tc[:prosopite_scan] = previous
        end
      else
        tc[:prosopite_scan] = false
      end
    end

    def resume
      tc[:prosopite_scan] = true
    end

    def scan?
      !!(tc[:prosopite_scan] && tc[:prosopite_query_counter] &&
         tc[:prosopite_query_holder] && tc[:prosopite_query_caller])
    end

    def finish
      return unless scan?

      tc[:prosopite_scan] = false

      begin
        create_notifications
        tc[:prosopite_notifications].present? ? send_notifications : []
      ensure
        tc[:prosopite_query_counter] = nil
        tc[:prosopite_query_holder] = nil
        tc[:prosopite_query_caller] = nil
        tc[:prosopite_query_duration] = nil
        tc[:prosopite_query_adapter] = nil
        tc[:prosopite_context] = nil
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
      tc[:prosopite_notifications] = {}

      tc[:prosopite_query_counter].each do |location_key, count|
        if count >= @min_n_queries
          db_adapter = tc[:prosopite_query_adapter][location_key]
          fingerprints = tc[:prosopite_query_holder][location_key].group_by do |q|
            begin
              db_adapter ? fingerprint(q, db_adapter) : fingerprint(q)
            rescue
              raise q
            end
          end

          queries = fingerprints.values.select { |q| q.size >= @min_n_queries }

          next unless queries.any?

          kaller = tc[:prosopite_query_caller][location_key].map(&:to_s)
          allow_list = (@allow_stack_paths + DEFAULT_ALLOW_LIST)
          is_allowed = kaller.any? { |f| allow_list.any? { |s| f.match?(s) } }
          is_focused = @focus_stack_paths.empty? ||
                       kaller.any? { |f| @focus_stack_paths.any? { |s| s.is_a?(Regexp) ? f.match?(s) : f.include?(s) } }

          if is_focused && !is_allowed
            duration_ms = tc[:prosopite_query_duration][location_key]
            queries.each do |q|
              tc[:prosopite_notifications][q] = { kaller: kaller, duration_ms: duration_ms }
            end
          end
        end
      end
    end

    def fingerprint(query, db_adapter = ActiveRecord::Base.connection_db_config.adapter)
      if db_adapter.match?(/mysql|trilogy/i)
        mysql_fingerprint(query)
      elsif db_adapter.match?(/postg/i)
        begin
          require 'pg_query'
        rescue LoadError => e
          msg = "Could not load the 'pg_query' gem. Add `gem 'pg_query'` to your Gemfile"
          raise LoadError, msg, e.backtrace
        end
        PgQuery.fingerprint(query)
      else
        # SQLite, Oracle etc. use double quotes for identifiers, not strings
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
      @custom_logger ||= false
      @rails_logger ||= false
      @stderr_logger ||= false
      @prosopite_logger ||= false

      notifications = tc[:prosopite_notifications].map do |queries, info|
        {
          queries: queries,
          call_stack: backtrace_cleaner.clean(info[:kaller]),
          duration_ms: info[:duration_ms],
          context: tc[:prosopite_context]
        }
      end

      notifications.each do |notification|
        ActiveSupport::Notifications.instrument('n_plus_one_queries.prosopite', notification)
      end

      notifications_str = notifications.map { |notification| notification_message(notification) }.join

      @custom_logger.warn(notifications_str) if @custom_logger

      Rails.logger.warn(red(notifications_str)) if @rails_logger
      $stderr.puts(red(notifications_str)) if @stderr_logger

      if @prosopite_logger
        File.open(File.join(Rails.root, 'log', 'prosopite.log'), 'a') do |f|
          f.puts(notifications_str)
        end
      end

      raise NPlusOneQueriesError.new(notifications_str) if raise?

      notifications
    end

    def notification_message(notification)
      queries = notification[:queries]
      duration_ms = notification[:duration_ms]

      details = []
      details << "#{queries.count} queries" if @display_query_count
      details << "#{duration_ms.round(1)}ms" if duration_ms
      details_str = details.any? ? " (#{details.join(', ')})" : ''

      message = String.new("N+1 queries detected#{details_str}:\n")

      queries_to_display =
        if @display_max_n_queries
          queries.take(@display_max_n_queries)
        else
          queries
        end

      queries_to_display.each { |q| message << "  #{q}\n" }

      message << "Call stack:\n"
      notification[:call_stack].each do |f|
        message << "  #{f}\n"
      end

      if notification[:context]
        message << "Context:\n"
        notification[:context].to_s.each_line do |line|
          message << "  #{line.chomp}\n"
        end
      end

      message << "\n"
    end

    def red(str)
      str.split("\n").map { |line| "\e[91m#{line}\e[0m" }.join("\n")
    end

    def ignore_query?(sql)
      @ignore_queries ||= []
      @ignore_queries.any? { |q| q === sql }
    end

    def ignore_location_path?(path)
      @ignore_location_paths ||= []
      @ignore_location_paths.any? { |p| path.match?(p) }
    end

    def subscribe
      @subscribed ||= false
      return if @subscribed

      ActiveSupport::Notifications.subscribe 'sql.active_record' do |_, start, finish, _, data|
        sql, name = data[:sql], data[:name]

        if scan? && name != "SCHEMA" && sql.include?('SELECT') && data[:cached].nil? && !ignore_query?(sql)
          query_caller = caller_locations
          connection = data[:connection]
          pool = connection&.pool
          ignored_paths = @ignore_location_paths
          # Queries on different databases (e.g. shards) can't be merged into one,
          # so they are kept under different location keys.
          # Calculate the location key with as few allocations as possible
          location_key = [(pool.db_config if pool.respond_to?(:db_config))].tap do |array|
            query_caller.each do |loc|
              next if ignored_paths && ignore_location_path?(loc.path)
              array << loc.path
              array << loc.lineno
            end
          end.hash

          tc[:prosopite_query_counter][location_key] += 1
          tc[:prosopite_query_holder][location_key] << sql
          tc[:prosopite_query_duration][location_key] += (finish - start) * 1000 if tc[:prosopite_query_duration]
          tc[:prosopite_query_adapter][location_key] ||= connection&.adapter_name if tc[:prosopite_query_adapter]

          if tc[:prosopite_query_counter][location_key] > 1
            tc[:prosopite_query_caller][location_key] = query_caller
          end
        end
      end

      @subscribed = true
    end
  end
end
