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

  def test_assoc_in_loop
    create_list(:leg, 10)

    Prosopite.scan
    Leg.last(10).each do |l|
      l.chair
    end

    assert_n_plus_one
  end

  def assert_n_plus_one
    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.finish
    end
  end
end
