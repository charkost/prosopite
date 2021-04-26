require 'test_helper'

class TestQueries < Minitest::Test
  def setup
    Prosopite.raise = true
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

  def test_scan_with_block_raising_error
    begin
      Prosopite.scan do
        raise ArgumentError # raise sample error
      end
    rescue ArgumentError
      assert_equal(false, Prosopite.scan?)
    end
  end

  def test_error_message
    Prosopite.raise = false

    message = Prosopite.scan do
      Chair.last(20).each do |c|
        c.legs.first
      end
    end

    assert_match(/N\+1 queries detected:/, message)
    Prosopite.raise = true
  end

  def assert_n_plus_one
    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.finish
    end
  end
end
