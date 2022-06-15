require 'test_helper'

class TestForceRaise < Minitest::Test
  def teardown
    Prosopite.raise = nil
  end

  def test_force_raise_raises_even_when_config_is_false
    Prosopite.raise = false

    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    refute Prosopite.raise?

    force_raise do
      Prosopite.scan

      Chair.last(20).each do |c|
        c.legs.last
      end

      assert_n_plus_one
    end

    refute Prosopite.raise?
  end

  private
  def assert_n_plus_one
    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.finish
    end
  end

  def force_raise(&block)
    Prosopite.force_raise
    yield
  ensure
    Prosopite.unforce_raise
  end
end
