require 'test_helper'

class TestQueries < Minitest::Test
  def setup
    Prosopite.raise = true
  end

  def teardown
    Prosopite.allow_stack_paths = nil
    Prosopite.ignore_queries = nil
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

  def test_resume_is_an_alias_of_scan
    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    Prosopite.resume
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
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
