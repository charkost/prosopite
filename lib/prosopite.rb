module Prosopite
  class NPlusOneQueriesError < StandardError; end
  class << self
    attr_writer :raise,
                :stderr_logger,
                :rails_logger,
                :prosopite_logger,
                :whitelist

    def scan
      subscribe

      @query_counter = Hash.new(0)
      @query_holder = Hash.new { |h, k| h[k] = [] }
      @query_caller = {}

      @whitelist ||= []
      @scan = true
    end

    def scan?
      @scan
    end

    def finish
      return unless scan?

      @notifications = {}

      @query_counter.each do |location_key, count|
        if count > 1
          fingerprints = @query_holder[location_key].map do |q|
            begin
              fingerprint(q)
            rescue
              raise q
            end
          end

          kaller = @query_caller[location_key]

          if fingerprints.uniq.size == 1 && !kaller.any? { |f| @whitelist.any? { |s| f.include?(s) } }
            queries = @query_holder[location_key]
            @notifications[queries] = kaller
          end
        end
      end

      @scan = false
      Prosopite.send_notifications if @notifications.present?
    end

    # Many thanks to https://github.com/genkami/fluent-plugin-query-fingerprint/
    def fingerprint(query)
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

      query.gsub!(/[0-9+-][0-9a-f.xb+-]*/, "?")
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
      notifications_str = ''

      @notifications.each do |queries, kaller|
        notifications_str << "N+1 queries detected:\n"
        queries.each { |q| notifications_str << "  #{q}\n" }
        notifications_str << "Call stack:\n"
        kaller.each do |f|
          notifications_str << "  #{f}\n" unless f.include?(Bundler.bundle_path.to_s)
        end
        notifications_str << "\n"
      end

      Rails.logger.warn(notifications_str) if @rails_logger
      $stderr.puts(notifications_str) if @stderr_logger

      if @prosopite_logger
        File.open(File.join(Rails.root, 'log', 'prosopite.log'), 'a') do |f|
          f.puts(notifications_str)
        end
      end

      raise NPlusOneQueriesError.new(notifications_str) if @raise
    end

    def subscribe
      return if @subscribed
      @subscribed = true

      ActiveSupport::Notifications.subscribe 'sql.active_record' do |_, _, _, _, data|
        sql = data[:sql]

        if scan? && sql.include?('SELECT') && data[:cached].nil?
          location_key = Digest::SHA1.hexdigest(caller.join)

          @query_counter[location_key] += 1
          @query_holder[location_key] << sql

          if @query_counter[location_key] > 1
            @query_caller[location_key] = caller.dup
          end
        end
      end
    end
  end
end
