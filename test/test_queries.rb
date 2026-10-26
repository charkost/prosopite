require 'test_helper'

class TestQueries < Minitest::Test
  def setup
    Prosopite.raise = true
  end

  def teardown
    Prosopite.allow_stack_paths = []
    Prosopite.focus_stack_paths = []
    Prosopite.ignore_queries = nil
    Prosopite.ignore_location_paths = nil
    Prosopite.enabled = true
  end

  def test_first_in_has_many_loop
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  def test_last_in_has_many_loop
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_n_plus_one
  end

  def test_pluck_in_has_many_loop
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.pluck(:id)
    end

    assert_n_plus_one
  end

  def test_separate_queries_in_and_out_of_block
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last.legs.pluck(:id); 1.times { Chair.last.legs.pluck };

    assert_no_n_plus_ones
  end

  def test_class_change
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).map{ |c| c.becomes(ArmChair) }.each do |ac|
      ac.legs.map(&:id)
    end

    assert_n_plus_one
  end

  def test_assoc_in_loop
    create_list(:leg, 10)

    Prosopite.scan
    Leg.last(10).each do |l|
      l.chair
    end

    assert_n_plus_one
  end

  def test_uniqueness_validations
    create_list(:chair, 10)

    Prosopite.scan
    Chair.last(10).each do |c|
      c.update(name: "#{c.name} + 1")
    end
    Prosopite.finish
  end

  def test_preloading_multiple_assocs_with_same_class
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.includes(:legs, :feet).last(20)
    Prosopite.finish
  end

  def test_preloader_loop
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan

    preloader = ActiveRecord::Associations::Preloader
    Chair.last(20).map do |chair|
      preloader.new(records: [chair], associations: [:legs]).call
      chair.legs
    end

    assert_n_plus_one
  end

  def test_scan_with_block
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.scan do
        Chair.last(20).each do |c|
          c.legs.first
        end
      end
    end
  end

  def test_nested_scan_with_block
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.scan do
        Prosopite.scan do
          Chair.last(20).each do |c|
            c.legs.first
          end
        end
      end
    end
  end

  def test_scan_with_block_when_not_enabled
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.enabled = false

    Prosopite.scan do
      Chair.last(20).each do |c|
        c.legs.last
      end
    end

    assert_no_n_plus_ones
  end

  def test_pause_with_no_error_after_resume
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan

    Prosopite.pause
    Chair.last(20).each do |c|
      c.legs.last
    end

    Prosopite.resume

    assert_no_n_plus_ones
  end

  def test_pause_with_ignore_pauses
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_pauses = true
    Prosopite.scan

    Prosopite.pause
    Chair.last(20).each do |c|
      c.legs.last
    end

    Prosopite.resume
    Prosopite.ignore_pauses = false

    assert_n_plus_one
  end

  def test_pause_with_error_after_resume
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan

    Prosopite.pause
    Prosopite.resume

    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_n_plus_one
  end

  def test_pause_and_do_not_resume
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan

    Prosopite.pause

    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_no_n_plus_ones
  end

  def test_pause_with_a_block
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan

    result = Prosopite.pause do
      Chair.last(20).each do |c|
        c.legs.last
      end

      :some_result_here
    end

    assert_equal(:some_result_here, result)

    # Ensures that scan mode is re-enabled after the block
    assert_equal(true, Prosopite.scan?)

    assert_no_n_plus_ones
  end

  def test_nested_pause_blocks
    # 10 chairs, 4 legs each
    chairs = create_list(:chair, 10)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan

    inner_result = nil
    outer_result = Prosopite.pause do
      inner_result = Prosopite.pause do
        :result
      end

      Chair.last(20).each do |c|
        c.legs.last
      end

      :outer_result
    end

    assert_equal(:result, inner_result)

    assert_equal(:outer_result, outer_result)

    assert_no_n_plus_ones
  end

  def test_pause_with_a_block_raising_error
    Prosopite.scan

    begin
      Prosopite.pause do
        raise ArgumentError # raise sample error
      end
    rescue ArgumentError
    end

    # Ensures that scan mode is re-enabled after the block,
    # even if there is an errror
    assert_equal(true, Prosopite.scan?)

    assert_no_n_plus_ones
  end

  def test_scan_with_block_raising_error
    begin
      Prosopite.scan do
        raise ArgumentError # raise sample error
      end
    rescue ArgumentError
      assert_equal(false, Prosopite.scan?)
    end
  end

  def test_scan_with_block_returns_result
    actual_result = Prosopite.scan do
      :result_of_block
    end

    assert_equal(:result_of_block, actual_result)
  end

  def test_allow_stack_paths
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.allow_stack_paths = ["test/test_queries.rb"]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_no_n_plus_ones
  end

  def test_allow_stack_paths_with_regex
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    # ...prosopite/test/test_queries.rb:195:in `block in test_allow_stack_paths_with_regex'
    Prosopite.allow_stack_paths = [/test_queries.*test_allow_stack_paths_with_regex/]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_no_n_plus_ones
  end

  def test_allow_stack_paths_does_not_match_query_source
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.allow_stack_paths = ["some_random_path.rb"]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  def test_focus_stack_paths
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.focus_stack_paths = ['test_queries.rb']

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  def test_focus_stack_paths_not_in_call_stack
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.focus_stack_paths = [%r{/not_in_call_stack/}]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_no_n_plus_ones
  end

  def test_focus_stack_paths_are_substrings
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.focus_stack_paths = ['block (2 levels) in ']

    Prosopite.scan
    [1].each do
      Chair.last(20).each do |c|
        c.legs.first
      end
    end

    assert_n_plus_one
  end

  def test_allow_stack_paths_over_focus_stack_paths
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.focus_stack_paths = ['test_queries.rb']
    Prosopite.allow_stack_paths = ['test_queries.rb']

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_no_n_plus_ones
  end

  def test_ignore_queries
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_queries = [/legs/]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_no_n_plus_ones
  end

  def test_ignore_queries_with_exact_match
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_queries = [%(SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = ? ORDER BY "legs"."id" DESC LIMIT ?)]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_no_n_plus_ones
  end

  def test_ignore_queries_mismatch
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_queries = [/arms/]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_n_plus_one
  end

  def test_ignore_queries_with_incorrect_query_match
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_queries = [%(SELECT "chairs".* FROM "chairs" ORDER BY "chairs"."id" DESC LIMIT ?)]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_n_plus_one
  end

  def test_ignore_location_paths
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_location_paths = ['minitest']

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  def test_ignore_location_paths_with_regex
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_location_paths = [/minitest/]

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  def test_ignore_location_paths_nil_by_default
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  def test_fingerprints_with_the_adapter_of_the_query_connection
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    # Primary db is postgres, but these queries run on a sqlite connection
    primary_db_config = Struct.new(:adapter).new('postgresql')
    ActiveRecord::Base.singleton_class.alias_method(:original_connection_db_config, :connection_db_config)
    ActiveRecord::Base.define_singleton_method(:connection_db_config) { primary_db_config }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  ensure
    ActiveRecord::Base.singleton_class.alias_method(:connection_db_config, :original_connection_db_config)
    ActiveRecord::Base.singleton_class.remove_method(:original_connection_db_config)
  end

  def test_queries_on_different_shards
    shard_one, shard_two = %w[shard_one shard_two].map do |name|
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new('test', name, adapter: 'sqlite3')
      Struct.new(:adapter_name, :pool).new('SQLite', Struct.new(:db_config).new(db_config))
    end

    Prosopite.scan
    [shard_one, shard_two].each do |connection|
      ActiveSupport::Notifications.instrument(
        'sql.active_record',
        sql: 'SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = 1',
        name: 'Leg Load',
        connection: connection
      )
    end

    assert_no_n_plus_ones
  end

  def test_queries_on_the_same_shard
    shard_one = Struct.new(:adapter_name, :pool).new(
      'SQLite',
      Struct.new(:db_config).new(ActiveRecord::DatabaseConfigurations::HashConfig.new('test', 'shard_one', adapter: 'sqlite3'))
    )

    Prosopite.scan
    [shard_one, shard_one].each do |connection|
      ActiveSupport::Notifications.instrument(
        'sql.active_record',
        sql: 'SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = 1',
        name: 'Leg Load',
        connection: connection
      )
    end

    assert_n_plus_one
  end

  def test_queries_on_a_connection_without_a_pool_config
    # e.g. connections made outside a connection pool on Active Record < 7.1
    connection = Struct.new(:adapter_name, :pool).new('SQLite', Object.new)

    Prosopite.scan
    ActiveSupport::Notifications.instrument(
      'sql.active_record',
      sql: 'SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = 1',
      name: 'Leg Load',
      connection: connection
    )

    assert_no_n_plus_ones
  end

  def test_allow_list_is_deprecated
    assert_output(nil, /Prosopite.allow_list= is deprecated and will be removed in 3.0/) do
      Prosopite.allow_list = ['legacy']
    end

    assert_equal ['legacy'], Prosopite.allow_stack_paths
  end

  def test_scan_without_a_block_while_scanning
    Prosopite.scan

    assert_nil Prosopite.scan
    assert Prosopite.scan?

    assert_no_n_plus_ones
  end

  def test_pause_during_an_event
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
    FactoryBot.define do
      factory :leg_with_n_plus_one, class: 'Leg' do
        chair
        after(:create) { Leg.last(20).each(&:chair) }
      end
    end

    Prosopite.scan
    create(:leg_with_n_plus_one)
    assert_n_plus_one

    subscriber = Prosopite.pause_during('factory_bot.run_factory')
    Prosopite.scan
    create(:leg_with_n_plus_one)
    assert_no_n_plus_ones

    Prosopite.ignore_pauses = true
    Prosopite.scan
    create(:leg_with_n_plus_one)
    assert_n_plus_one
  ensure
    Prosopite.ignore_pauses = false
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    FactoryBot.factories.instance_variable_get(:@items)&.delete(:leg_with_n_plus_one)
  end

  def test_pause_during_an_event_outside_a_scan
    subscriber = Prosopite.pause_during('test.prosopite')

    assert_equal :done, ActiveSupport::Notifications.instrument('test.prosopite') { :done }
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def test_pause_and_resume_outside_a_scan
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    assert_equal(:result, Prosopite.pause { :result })
    Prosopite.resume
    Prosopite.pause

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_n_plus_one
  end

  def test_finish_while_paused
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end
    Prosopite.pause

    assert_n_plus_one
    refute Prosopite.scan?
  end

  def test_scan_while_paused_replaces_the_scan
    Prosopite.scan
    paused_state = Thread.current[:prosopite_state]
    Chair.first
    Prosopite.pause

    Prosopite.scan
    Chair.first

    assert Prosopite.scan?
    assert_empty paused_state[:prosopite_query_holder]
    assert_no_n_plus_ones
  end

  def test_block_scan_that_raises
    state = nil

    assert_raises(RuntimeError) do
      Prosopite.scan do
        state = Thread.current[:prosopite_state]
        Chair.first
        raise 'boom'
      end
    end

    refute Prosopite.scan?
    assert_nil Thread.current[:prosopite_state]
    assert_empty state[:prosopite_query_holder]
  end

  def test_fingerprint_override_without_the_adapter
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    # Like extensions that override fingerprint(query), e.g. prosopite_todo
    fingerprint = Prosopite.singleton_class.instance_method(:fingerprint)
    Prosopite.singleton_class.define_method(:fingerprint) { |query| fingerprint.bind_call(self, query) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.last
    end

    assert_n_plus_one
  ensure
    Prosopite.singleton_class.define_method(:fingerprint, fingerprint)
  end

  def test_pause_with_a_block_with_ignore_pauses
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.ignore_pauses = true
    Prosopite.scan

    result = Prosopite.pause do
      Chair.last(20).each do |c|
        c.legs.last
      end

      :some_result_here
    end

    assert_equal(:some_result_here, result)
    assert_n_plus_one
  ensure
    Prosopite.ignore_pauses = false
  end

  def test_queries_without_a_connection
    Prosopite.scan
    2.times do |i|
      ActiveSupport::Notifications.instrument(
        'sql.active_record',
        sql: %(SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = #{i}),
        name: 'Leg Load'
      )
    end

    assert_n_plus_one
  end

  def test_different_queries_from_the_same_location
    create(:leg)

    Prosopite.scan
    [Chair, Leg].each(&:first)

    assert_no_n_plus_ones
  end

  def test_query_that_cannot_be_fingerprinted
    connection = Struct.new(:adapter_name, :pool).new('PostgreSQL', nil)
    query = 'SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = ?'

    Prosopite.scan
    2.times do
      ActiveSupport::Notifications.instrument('sql.active_record', sql: query, name: 'Leg Load', connection: connection)
    end

    error = assert_raises(RuntimeError) { Prosopite.finish }
    assert_equal query, error.message
    assert_kind_of PgQuery::ParseError, error.cause
  end

  def test_postgresql_without_pg_query
    forget_pg_query
    Prosopite.singleton_class.define_method(:require) do |name|
      raise LoadError, "cannot load such file -- #{name}"
    end

    # The built-in fingerprint, which collapses IN lists of placeholders
    assert_equal(
      Prosopite.fingerprint('SELECT "legs".* FROM "legs" WHERE "legs"."id" IN ($1, $2)', 'postgresql'),
      Prosopite.fingerprint('SELECT "legs".* FROM "legs" WHERE "legs"."id" IN ($1, $2, $3)', 'postgresql')
    )
    refute_equal(
      Prosopite.fingerprint('SELECT "legs".* FROM "legs" WHERE "legs"."id" = $1', 'postgresql'),
      Prosopite.fingerprint('SELECT "chairs".* FROM "chairs" WHERE "chairs"."id" = $1', 'postgresql')
    )
  ensure
    Prosopite.singleton_class.send(:remove_method, :require)
    forget_pg_query
  end

  def test_ignore_location_paths_matches_are_cached
    Prosopite.ignore_location_paths = ['minitest']
    cache = Prosopite.instance_variable_get(:@ignored_paths)
    path = caller_locations(0, 1).first.path

    10_000.times { |i| cache["path #{i}"] = false }
    Prosopite.scan
    Chair.first

    refute_includes cache.keys, 'path 0'
    assert_equal false, cache[path]
    assert_no_n_plus_ones
  end

  def test_same_n_plus_one_in_two_locations
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.raise = false
    Prosopite.scan
    chairs = Chair.last(20)
    chairs.each { |c| c.legs.first }
    chairs.each { |c| c.legs.first }

    # Their queries are the same, with bind parameters
    assert_equal 2, Prosopite.finish.size
  end

  def test_sample_rate
    Prosopite.sample_rate = 0.0
    assert_equal(:result, Prosopite.scan { :result })
    Prosopite.scan
    refute Prosopite.scan?

    Prosopite.sample_rate = 1.0
    Prosopite.scan
    assert Prosopite.scan?
    assert_no_n_plus_ones
  ensure
    Prosopite.sample_rate = nil
  end

  def test_sample_rate_must_be_a_share
    Prosopite.sample_rate = '0.5'
    assert_equal 0.5, Prosopite.sample_rate

    assert_raises(ArgumentError) { Prosopite.sample_rate = 1.5 }
    assert_raises(ArgumentError) { Prosopite.sample_rate = 'all' }
  ensure
    Prosopite.sample_rate = nil
  end

  def test_min_duration_ms
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.min_duration_ms = 60_000
    Prosopite.scan
    Chair.last(20).each { |c| c.legs.first }
    assert_no_n_plus_ones

    Prosopite.min_duration_ms = 0
    Prosopite.scan
    Chair.last(20).each { |c| c.legs.first }
    assert_n_plus_one
  ensure
    Prosopite.min_duration_ms = nil
  end

  def test_min_n_queries
    chairs = create_list(:chair, 4)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.min_n_queries = 5

    Prosopite.scan
    Chair.last(4).each do |c|
      c.legs.last
    end

    assert_no_n_plus_ones
  ensure
    Prosopite.min_n_queries = 2
  end

  def test_timing_in_notification
    chairs = create_list(:chair, 5)
    chairs.each { |c| create_list(:leg, 2, chair: c) }

    error = assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.scan do
        Chair.last(5).each { |c| c.legs.first }
      end
    end

    assert_match(/N\+1 queries detected \(\d+\.\d+ms\)/, error.message)
  end

  def test_context_in_notification
    chairs = create_list(:chair, 5)
    chairs.each { |c| create_list(:leg, 2, chair: c) }

    error = assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.scan("GET /widgets/1") do
        Chair.last(5).each { |c| c.legs.first }
      end
    end

    assert_match(/Context:\n  GET \/widgets\/1\n\n\z/, error.message)
  end

  def test_multiline_context_in_notification
    chairs = create_list(:chair, 5)
    chairs.each { |c| create_list(:leg, 2, chair: c) }

    error = assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.scan("GET /widgets/1\nUser: 42") do
        Chair.last(5).each { |c| c.legs.first }
      end
    end

    assert_match(/Context:\n  GET \/widgets\/1\n  User: 42\n\n\z/, error.message)
  end

  def test_display_max_n_queries
    log_output = StringIO.new
    Prosopite.custom_logger = Logger.new(log_output)
    Prosopite.display_max_n_queries = 3

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one

    log_lines = log_output.string.split("\n").map(&:strip)
    repeated_query =
      %(SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = ? ORDER BY "legs"."id" ASC LIMIT ?)

    assert_equal log_lines.count(repeated_query), 3
  ensure
    Prosopite.custom_logger = nil
    Prosopite.display_max_n_queries = nil
  end

  def test_display_query_count
    log_output = StringIO.new
    Prosopite.custom_logger = Logger.new(log_output)
    Prosopite.display_query_count = true

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one

    assert_includes log_output.string, 'N+1 queries detected (20 queries, '
  ensure
    Prosopite.custom_logger = nil
    Prosopite.display_query_count = false
  end

  private

  def forget_pg_query
    Prosopite.remove_instance_variable(:@pg_query) if Prosopite.instance_variable_defined?(:@pg_query)
  end

  def assert_n_plus_one
    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.finish
    end
  end

  def assert_no_n_plus_ones
    Prosopite.finish
  end
end
