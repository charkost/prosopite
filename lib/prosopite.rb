
module Prosopite
  DEFAULT_ALLOW_LIST = %w(active_record/associations/preloader active_record/validations/uniqueness)

  class NPlusOneQueriesError < StandardError; end
  class << self
    attr_writer :raise,
                :stderr_logger,
                :rails_logger,
                :prosopite_logger,
                :custom_logger,
                :allow_stack_paths,
                :ignore_queries

    def allow_list=(value)
      puts "Prosopite.allow_list= is deprecated. Use Prosopite.allow_stack_paths= instead."

      self.allow_stack_paths = value
    end

    def scan
      tc[:prosopite_scan] ||= false
      return if scan?

      subscribe

      tc[:prosopite_query_counter] = Hash.new(0)
      tc[:prosopite_query_holder] = Hash.new { |h, k| h[k] = [] }
      tc[:prosopite_query_caller] = {}

      @allow_stack_paths ||= []

      tc[:prosopite_scan] = true

      if block_given?
        begin
          yield
          finish
        ensure
          tc[:prosopite_scan] = false
        end
      end
    end

    def tc
      Thread.current
    end

    def pause
      tc[:prosopite_scan] = false

      if block_given?
        begin
          yield
        ensure
          tc[:prosopite_scan] = true
        end
      end
    end

    def resume
      scan
    end

    def scan?
      tc[:prosopite_scan]
    end

    def finish
      return unless scan?

      tc[:prosopite_scan] = false

      create_notifications
      send_notifications if tc[:prosopite_notifications].present?
    end

    def create_notifications
      tc[:prosopite_notifications] = {}

      tc[:prosopite_query_counter].each do |location_key, count|
        if count > 1
          fingerprints = tc[:prosopite_query_holder][location_key].map do |q|
            begin
              fingerprint(q)
            rescue
              raise q
            end
          end

          next unless fingerprints.uniq.size == 1

          kaller = tc[:prosopite_query_caller][location_key]
          allow_list = (@allow_stack_paths + DEFAULT_ALLOW_LIST)
          is_allowed = kaller.any? { |f| allow_list.any? { |s| f.match?(s) } }

          unless is_allowed
            queries = tc[:prosopite_query_holder][location_key]
            tc[:prosopite_notifications][queries] = kaller
          end
        end
      end
    end

    def fingerprint(query)
      if ActiveRecord::Base.connection.adapter_name.downcase.include?('mysql')
        mysql_fingerprint(query)
      else
        begin
          require 'pg_query'
        rescue LoadError => e
          msg = "Could not load the 'pg_query' gem. Add `gem 'pg_query'` to your Gemfile"
          raise LoadError, msg, e.backtrace
        end
        PgQuery.fingerprint(query)
      end
    end

    # Many thanks to https://github.com/genkami/fluent-plugin-query-fingerprint/
    def mysql_fingerprint(query)
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
      query.gsub!(/".*?"/m, "?")
      query.gsub!(/'.*?'/m, "?")

      query.gsub!(/\btrue\b|\bfalse\b/i, "?")

      query.gsub!(/[0-9+-][0-9a-f.x+-]*/, "?")
      query.gsub!(/[xb.+-]\?/, "?")

      query.strip!
      query.gsub!(/[ \n\t\r\f]+/, " ")
      query.downcase!

      query.gsub!(/\bnull\b/i, "?")

      query.gsub!(/\b(in|values?)(?:[\s,]*\([\s?,]*\))+/, "\\1(?+)")

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
      @raise ||= false

      notifications_str = ''

      tc[:prosopite_notifications].each do |queries, kaller|
        notifications_str << "N+1 queries detected:\n"
        queries.each { |q| notifications_str << "  #{q}\n" }
        notifications_str << "Call stack:\n"
        kaller.each do |f|
          notifications_str << "  #{f}\n" unless f.include?(Bundler.bundle_path.to_s)
        end
        notifications_str << "\n"
      end

      @custom_logger.warn(notifications_str) if @custom_logger

      Rails.logger.warn(red(notifications_str)) if @rails_logger
      $stderr.puts(red(notifications_str)) if @stderr_logger

      if @prosopite_logger
        File.open(File.join(Rails.root, 'log', 'prosopite.log'), 'a') do |f|
          f.puts(notifications_str)
        end
      end

      raise NPlusOneQueriesError.new(notifications_str) if @raise
    end

    def red(str)
      str.split("\n").map { |line| "\e[91m#{line}\e[0m" }.join("\n")
    end

    def ignore_query?(sql)
      @ignore_queries ||= []
      @ignore_queries.any? { |q| q === sql }
    end

    def subscribe
      @subscribed ||= false
      return if @subscribed

      ActiveSupport::Notifications.subscribe 'sql.active_record' do |_, _, _, _, data|
        sql, name = data[:sql], data[:name]

        if scan? && name != "SCHEMA" && sql.include?('SELECT') && data[:cached].nil? && !ignore_query?(sql)
          location_key = Digest::SHA1.hexdigest(caller.join)

          tc[:prosopite_query_counter][location_key] += 1
          tc[:prosopite_query_holder][location_key] << sql

          if tc[:prosopite_query_counter][location_key] > 1
            tc[:prosopite_query_caller][location_key] = caller.dup
          end
        end
      end

      @subscribed = true
    end
  end
end
