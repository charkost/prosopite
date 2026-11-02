require 'prosopite'

module Prosopite
  # Reports the N+1 queries of redis-client:
  # - the same command on the same kind of key repeated from the same call stack, e.g.
  #   reading the name of each user in a loop
  # - reads of the same key from different places, e.g. the fields of a hash one by one
  # Pipelines run in one round trip, so they're not recorded.
  #
  #   require 'prosopite/redis'
  #   RedisClient.register(Prosopite::Redis::Middleware)
  module Redis
    ADAPTER = 'Redis'
    KEY_ADAPTER = 'Redis key'
    # Reads of a key that one command can combine
    KEY_READS = %w[GET HGET HMGET HEXISTS HGETALL].to_set.freeze
    # Commands can have large values, so only their start is recorded
    MAX_QUERY_LENGTH = 200

    # A middleware of redis-client that records each command in the running scan
    module Middleware
      def call(command, redis_config)
        return super unless Prosopite.scan?

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
        reply = super
        Prosopite::Redis.record(command, Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start)
        reply
      end
    end

    @hints = {}

    class << self
      # Key prefixes, and a hint to add to the fixes of the N+1 queries of their keys, e.g.
      # { 'user:' => 'Use User.fetch_profiles for many users' }
      attr_accessor :hints

      def record(command, duration_ms)
        # Without the frames of this file and of the middleware stack, which are the same for every command
        call_stack = caller_locations(2)
        query = query(command)
        location_key = Prosopite.record_query(query, adapter: ADAPTER, duration_ms: duration_ms, call_stack: call_stack)
        return unless location_key && KEY_READS.include?(command.first.to_s.upcase)

        # The key of the query, which the fingerprint and fixes of its N+1 get too
        record_key_read(key(query), query, duration_ms, location_key, call_stack)
      end

      # The command and its key, with the numbers and UUIDs of the key replaced
      def fingerprint(query)
        command, key = query.split(' ', 3)
        "#{command.downcase} #{normalize_key(key.to_s)}".strip
      end

      def fixes(query)
        ['Send the commands in one round trip, with pipelined, or a command for many keys like MGET', *hints_for(query)]
      end

      def key_fingerprint(query)
        normalize_key(key(query))
      end

      def key_fixes(query)
        fix = if query.match?(/\AGET /i)
                "Read #{key(query)} once and pass its value on"
              else
                "Read #{key(query)} once, e.g. the fields of a hash together with HMGET or HGETALL"
              end
        [fix, 'Around a write, use its reply, e.g. of HINCRBY, or a Lua script instead of reading again',
         *hints_for(query)]
      end

      private

      # Once a key is read from a second call stack, its reads are an N+1, counted together
      # with the reads of the keys with the same fingerprint, e.g. of each user in a loop.
      # The reads from the first call stack before are left to the check of commands.
      def record_key_read(key, query, duration_ms, location_key, call_stack)
        # Empty when another fiber paused the scan since the command was recorded
        reads = Prosopite.scan_data(KEY_ADAPTER) || {}
        first = reads[key]

        if first.nil?
          reads[key] = [location_key, query, duration_ms]
        elsif first == true || first[0] != location_key
          group = normalize_key(key)
          record_key_query(first[1], first[2], group, call_stack) unless first == true
          record_key_query(query, duration_ms, group, call_stack)
          reads[key] = true
        end
      end

      def record_key_query(query, duration_ms, group, call_stack)
        Prosopite.record_query(query, adapter: KEY_ADAPTER, location_key: group, duration_ms: duration_ms, call_stack: call_stack)
      end

      def key(query)
        query.split(' ', 3)[1].to_s
      end

      def hints_for(query)
        key = key(query)
        hints.select { |prefix, _| key.start_with?(prefix) }.values
      end

      # Each argument is cut before they're joined, as values can be large, and made valid
      # UTF-8, as values can be binary, e.g. compressed or marshalled
      def query(command)
        command.map do |arg|
          arg.to_s.byteslice(0, MAX_QUERY_LENGTH).force_encoding(Encoding::UTF_8).scrub
        end.join(' ')[0, MAX_QUERY_LENGTH]
      end

      def normalize_key(key)
        key.gsub(/\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/, '?').gsub(/\d+/, '?')
      end
    end

    Prosopite.register_adapter(ADAPTER, fingerprint: method(:fingerprint), fixes: method(:fixes))
    Prosopite.register_adapter(KEY_ADAPTER, fingerprint: method(:key_fingerprint), fixes: method(:key_fixes))
  end
end
