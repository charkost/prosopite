require 'test_helper'
require 'prosopite/redis'

class TestRedis < Minitest::Test
  # Stand-ins for the middleware stack of redis-client, which runs the command in the block
  class BasicMiddleware
    def call(command, _config)
      yield command
    end
    alias_method :call_pipelined, :call
  end

  class Middlewares < BasicMiddleware
    include Prosopite::Redis::Middleware
  end

  def test_the_same_command_in_a_loop
    n_plus_ones = Prosopite.n_plus_one_queries do
      [1, 2, 3].each { |id| redis('HGET', "user:#{id}", 'name') }
    end

    assert_equal 1, n_plus_ones.size
    assert_equal 'hget user:?', n_plus_ones.first[:fingerprint]
    assert_equal ['HGET user:1 name', 'HGET user:2 name', 'HGET user:3 name'], n_plus_ones.first[:queries]
    assert_match(/pipelined/, n_plus_ones.first[:fixes].first)
  end

  def test_reads_of_the_same_key_from_different_places
    n_plus_ones = Prosopite.n_plus_one_queries do
      redis('HGET', 'user:1', 'name')
      redis('HGET', 'user:1', 'email')
    end

    assert_equal 1, n_plus_ones.size
    assert_equal 'user:?', n_plus_ones.first[:fingerprint]
    assert_equal ['HGET user:1 name', 'HGET user:1 email'], n_plus_ones.first[:queries]
    assert_match(/user:1 once.*HMGET/, n_plus_ones.first[:fixes].first)
  end

  def test_reads_of_a_string_from_different_places
    n_plus_ones = Prosopite.n_plus_one_queries do
      redis('GET', 'settings')
      redis('GET', 'settings')
    end

    assert_equal ['Read settings once and pass its value on',
                  'Around a write, use its reply, e.g. of HINCRBY, or a Lua script instead of reading again'],
                 n_plus_ones.first[:fixes]
  end

  def test_lowercase_commands
    n_plus_ones = Prosopite.n_plus_one_queries do
      redis('hget', 'user:1', 'name')
      redis('hget', 'user:1', 'email')
    end

    assert_equal 'user:?', n_plus_ones.first[:fingerprint]
    assert_match(/HMGET/, n_plus_ones.first[:fixes].first)
  end

  def test_binary_values_and_keys_in_other_encodings
    n_plus_ones = Prosopite.n_plus_one_queries do
      [1, 2].each { |id| assert_equal 'reply to SET', redis('SET', "café:#{id}", "\xFF\x00".b * 500) }
    end

    assert_equal 'set café:?', n_plus_ones.first[:fingerprint]
    assert n_plus_ones.first[:queries].all? { |q| q.valid_encoding? && q.encoding == Encoding::UTF_8 }
    assert_equal [200, 200], n_plus_ones.first[:queries].map(&:size)
  end

  def test_reads_of_the_same_key_from_the_same_place
    n_plus_ones = Prosopite.n_plus_one_queries do
      3.times { redis('GET', 'user:1') }
    end

    assert_equal ['get user:?'], n_plus_ones.map { |n| n[:fingerprint] }
  end

  def test_reads_of_the_same_key_from_three_places
    n_plus_ones = Prosopite.n_plus_one_queries do
      redis('HGET', 'user:1', 'name')
      redis('HGET', 'user:1', 'email')
      redis('HEXISTS', 'user:1', 'admin')
    end

    assert_equal [3], n_plus_ones.map { |n| n[:queries].size }
  end

  def test_reads_of_the_same_keys_from_different_places_in_a_loop
    n_plus_ones = Prosopite.n_plus_one_queries do
      [1, 2, 3].each do |id|
        redis('HGET', "user:#{id}", 'name')
        redis('HGET', "user:#{id}", 'email')
      end
    end

    by_key = n_plus_ones.select { |n| n[:fingerprint] == 'user:?' }
    assert_equal [6], by_key.map { |n| n[:queries].size }
    assert_equal ['hget user:?', 'hget user:?'], (n_plus_ones - by_key).map { |n| n[:fingerprint] }
  end

  def test_writes_of_the_same_key_from_different_places
    n_plus_ones = Prosopite.n_plus_one_queries do
      redis('SET', 'user:1', 'a')
      redis('SET', 'user:1', 'b')
    end

    assert_empty n_plus_ones
  end

  def test_ignored_commands
    Prosopite.ignore_queries = [/user/]

    n_plus_ones = Prosopite.n_plus_one_queries do
      [1, 2].each { |id| redis('GET', "user:#{id}") }
      redis('GET', 'user:1')
    end

    assert_empty n_plus_ones
  ensure
    Prosopite.ignore_queries = nil
  end

  def test_hints_for_the_keys_of_an_n_plus_one
    Prosopite::Redis.hints = { 'user:' => 'Use User.fetch_profiles', 'session:' => 'Use Session.fetch_many' }

    n_plus_ones = Prosopite.n_plus_one_queries do
      [1, 2].each { |id| redis('GET', "user:#{id}") }
      redis('HGET', 'user:3', 'name')
      redis('HGET', 'user:3', 'email')
    end

    assert_equal [2, 3], n_plus_ones.map { |n| n[:fixes].size }
    assert_equal ['Use User.fetch_profiles'] * 2, n_plus_ones.map { |n| n[:fixes].last }
  ensure
    Prosopite::Redis.hints = {}
  end

  def test_the_reply
    Prosopite.n_plus_one_queries do
      assert_equal 'reply to GET', redis('GET', 'user:1')
    end
    assert_equal 'reply to GET', redis('GET', 'user:1')
  end

  def test_a_pipeline_in_a_loop
    n_plus_ones = Prosopite.n_plus_one_queries do
      [1, 2].each { |id| pipelined(['HGET', "user:#{id}", 'name'], ['HGET', "user:#{id}", 'email']) }
    end

    assert_empty n_plus_ones
  end

  def test_a_command_with_a_large_value
    n_plus_ones = Prosopite.n_plus_one_queries do
      [1, 2].each { |id| redis('SET', "user:#{id}", 'x' * 1000) }
    end

    assert_equal [200, 200], n_plus_ones.first[:queries].map(&:size)
    assert_equal 'set user:?', n_plus_ones.first[:fingerprint]
  end

  def test_the_fingerprint_of_uuids_and_commands_without_a_key
    assert_equal 'get user:?:name', Prosopite::Redis.fingerprint('GET user:0b5e8f0e-3c1a-4c4e-9d1e-2f6a1b7c8d9e:name')
    assert_equal 'ping', Prosopite::Redis.fingerprint('PING')
  end

  private

  def redis(*command)
    Middlewares.new.call(command, nil) { |c| "reply to #{c.first}" }
  end

  def pipelined(*commands)
    Middlewares.new.call_pipelined(commands, nil) { |c| c.map { 'reply' } }
  end
end
