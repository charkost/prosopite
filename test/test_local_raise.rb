require 'test_helper'

class TestLocalRaise < Minitest::Test
  def teardown
    Prosopite.raise = nil
  end

  def test_local_raise_raises_even_when_config_is_false
    Prosopite.raise = false

    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }

    refute Prosopite.raise?

    local_raise do
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

  def local_raise(&block)
    Prosopite.start_raise
    yield
  ensure
    Prosopite.stop_raise
  end
end
