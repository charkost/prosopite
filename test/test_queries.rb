require 'test_helper'

class TestQueries < Minitest::Test
  def setup
    Prosopite.raise = true
  end

  def teardown
    Prosopite.allow_stack_paths = []
    Prosopite.ignore_queries = nil
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

  private
  def assert_n_plus_one
    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.finish
    end
  end

  def assert_no_n_plus_ones
    Prosopite.finish
  end
end
