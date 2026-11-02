require 'test_helper'

class TestQuerySources < Minitest::Test
  def test_queries_from_the_same_call_stack
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new

    n_plus_ones = Prosopite.n_plus_one_queries do
      3.times { |i| Prosopite.record_query("GET user:#{i}", adapter: 'Cache') }
    end

    assert_equal 1, n_plus_ones.size
    assert_equal ['GET user:0', 'GET user:1', 'GET user:2'], n_plus_ones.first[:queries]
    assert n_plus_ones.first[:call_stack].any? { |f| f.include?('test_query_sources.rb') }
  ensure
    Prosopite.backtrace_cleaner = nil
  end

  def test_the_fingerprint_of_a_registered_adapter
    Prosopite.register_adapter('Cache', fingerprint: ->(query) { query.split(':').first })

    n_plus_ones = Prosopite.n_plus_one_queries do
      ['GET user:1', 'GET user:2', 'GET user:abc'].each { |q| Prosopite.record_query(q, adapter: 'Cache') }
    end

    assert_equal ['GET user'], n_plus_ones.map { |n| n[:fingerprint] }
    assert_equal 3, n_plus_ones.first[:queries].size
  ensure
    Prosopite.unregister_adapter('Cache')
  end

  def test_the_fingerprint_of_another_adapter
    Prosopite.register_adapter('Cache', fingerprint: ->(query) { query.split(':').first })

    assert_equal 'get user:?', Prosopite.fingerprint('GET user:1', 'Search')
    assert_equal 'select * from chairs where id = ?', Prosopite.fingerprint('SELECT * FROM chairs WHERE id = 1', 'SQLite')
  ensure
    Prosopite.unregister_adapter('Cache')
  end

  def test_the_fixes_of_a_registered_adapter
    Prosopite.register_adapter('Cache', fingerprint: ->(query) { query }, fixes: ->(query) { ["MGET instead of #{query}"] })

    n_plus_ones = Prosopite.n_plus_one_queries do
      2.times { Prosopite.record_query('GET user:1', adapter: 'Cache') }
    end

    assert_equal ['MGET instead of GET user:1'], n_plus_ones.first[:fixes]
  ensure
    Prosopite.unregister_adapter('Cache')
  end

  def test_fixes_of_a_registered_adapter_when_fixes_are_off
    Prosopite.suggest_fixes = false
    Prosopite.register_adapter('Cache', fingerprint: ->(query) { query }, fixes: ->(_query) { ['MGET'] })

    n_plus_ones = Prosopite.n_plus_one_queries do
      2.times { Prosopite.record_query('GET user:1', adapter: 'Cache') }
    end

    assert_empty n_plus_ones.first[:fixes]
  ensure
    Prosopite.suggest_fixes = nil
    Prosopite.unregister_adapter('Cache')
  end

  def test_no_fixes_of_a_registered_adapter
    Prosopite.register_adapter('Cache', fingerprint: ->(query) { query })

    n_plus_ones = Prosopite.n_plus_one_queries do
      2.times { Prosopite.record_query('GET user:1', adapter: 'Cache') }
    end

    assert_empty n_plus_ones.first[:fixes]
  ensure
    Prosopite.unregister_adapter('Cache')
  end

  def test_fixes_of_a_registered_adapter_that_fail
    Prosopite.register_adapter('Cache', fingerprint: ->(query) { query }, fixes: ->(_query) { raise 'boom' })

    n_plus_ones = Prosopite.n_plus_one_queries do
      2.times { Prosopite.record_query('GET user:1', adapter: 'Cache') }
    end

    assert_equal 1, n_plus_ones.size
    assert_empty n_plus_ones.first[:fixes]
  ensure
    Prosopite.unregister_adapter('Cache')
  end

  def test_scan_data
    assert_nil Prosopite.scan_data('Cache')

    first_scan = Prosopite.n_plus_one_queries do
      Prosopite.scan_data('Cache')[:seen] = true
      Prosopite.pause { assert_nil Prosopite.scan_data('Cache') }
      assert Prosopite.scan_data('Cache')[:seen]
      assert_empty Prosopite.scan_data('Search')
    end
    Prosopite.n_plus_one_queries { assert_empty Prosopite.scan_data('Cache') }

    assert_empty first_scan
    assert_nil Prosopite.scan_data('Cache')
  end

  def test_where_records_are_loaded_after_many_single_queries
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new
    create_list(:chair, 2).each { |c| create(:leg, chair: c) }

    notification = Prosopite.n_plus_one_queries do
      Prosopite::MAX_SINGLE_CALLERS.times { |i| Prosopite.record_query("GET user:#{i}", adapter: 'Cache', location_key: i) }
      chairs = Chair.last(2); @line = __LINE__
      chairs.each { |c| c.legs.first }
    end.first

    assert_match(/where the chairs are loaded, at .*test_query_sources.rb:#{@line}\z/, notification[:fixes].first)
  ensure
    Prosopite.backtrace_cleaner = nil
  end

  def test_queries_from_different_call_stacks
    n_plus_ones = Prosopite.n_plus_one_queries do
      Prosopite.record_query('GET user:1', adapter: 'Cache')
      Prosopite.record_query('GET user:2', adapter: 'Cache')
    end

    assert_empty n_plus_ones
  end

  def test_queries_with_the_same_location_key_from_different_call_stacks
    n_plus_ones = Prosopite.n_plus_one_queries do
      Prosopite.record_query('GET user:1', adapter: 'Cache', location_key: 'user')
      Prosopite.record_query('GET user:1', adapter: 'Cache', location_key: 'user')
    end

    assert_equal [['GET user:1', 'GET user:1']], n_plus_ones.map { |n| n[:queries] }
  end

  def test_location_keys_of_different_adapters
    n_plus_ones = Prosopite.n_plus_one_queries do
      Prosopite.record_query('GET user:1', adapter: 'Cache', location_key: 'user')
      Prosopite.record_query('GET user:1', adapter: 'Search', location_key: 'user')
    end

    assert_empty n_plus_ones
  end

  def test_the_returned_location_key
    location_keys = []
    Prosopite.n_plus_one_queries do
      2.times { location_keys << Prosopite.record_query('GET user:1', adapter: 'Cache') }
      location_keys << Prosopite.record_query('GET user:1', adapter: 'Cache')
    end

    assert_equal location_keys[0], location_keys[1]
    refute_equal location_keys[0], location_keys[2]
  end

  def test_outside_a_scan
    assert_nil Prosopite.record_query('GET user:1', adapter: 'Cache')
  end

  def test_during_a_pause
    n_plus_ones = Prosopite.n_plus_one_queries do
      Prosopite.pause do
        3.times { |i| Prosopite.record_query("GET user:#{i}", adapter: 'Cache') }
      end
    end

    assert_empty n_plus_ones
  end

  def test_ignored_queries
    Prosopite.ignore_queries = [/user/]

    n_plus_ones = Prosopite.n_plus_one_queries do
      3.times { |i| Prosopite.record_query("GET user:#{i}", adapter: 'Cache') }
    end

    assert_empty n_plus_ones
  ensure
    Prosopite.ignore_queries = nil
  end

  def test_the_duration_and_call_stack_of_the_source
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new
    call_stack = caller_locations

    n_plus_ones = Prosopite.n_plus_one_queries do
      2.times { |i| Prosopite.record_query("GET user:#{i}", adapter: 'Cache', duration_ms: 1.5, call_stack: call_stack) }
    end

    assert_equal 3.0, n_plus_ones.first[:duration_ms]
    refute n_plus_ones.first[:call_stack].any? { |f| f.include?('test_query_sources.rb') }
  ensure
    Prosopite.backtrace_cleaner = nil
  end
end
