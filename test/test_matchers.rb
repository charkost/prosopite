require 'test_helper'
require 'rspec/expectations'
require 'prosopite/rspec'
require 'prosopite/minitest'

class TestMatchers < Minitest::Test
  include RSpec::Matchers

  def setup
    Prosopite.raise = true

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.raise = nil
  end

  def test_rspec_matcher
    expect { n_plus_one }.to have_n_plus_one_queries
    expect { Chair.last(20).map(&:name) }.not_to have_n_plus_one_queries
  end

  def test_rspec_matcher_failure_messages
    error = assert_raises(RSpec::Expectations::ExpectationNotMetError) do
      expect { n_plus_one }.not_to have_n_plus_one_queries
    end
    assert_match(/expected no N\+1 queries, but there were:\n\nN\+1 queries detected/, error.message)
    assert_includes error.message, 'SELECT "legs".* FROM "legs"'

    error = assert_raises(RSpec::Expectations::ExpectationNotMetError) do
      expect { Chair.last(20).map(&:name) }.to have_n_plus_one_queries
    end
    assert_equal 'expected N+1 queries, but there were none', error.message
  end

  def test_minitest_assertions
    assert_n_plus_one_queries { n_plus_one }
    assert_no_n_plus_one_queries { Chair.last(20).map(&:name) }
  end

  def test_minitest_assertion_failure_messages
    error = assert_raises(Minitest::Assertion) do
      assert_no_n_plus_one_queries { n_plus_one }
    end
    assert_match(/Expected no N\+1 queries, but there were:\n\nN\+1 queries detected/, error.message)

    error = assert_raises(Minitest::Assertion) do
      assert_n_plus_one_queries { Chair.last(20).map(&:name) }
    end
    assert_equal 'Expected N+1 queries, but there were none', error.message
  end

  def test_n_plus_one_queries
    notifications = Prosopite.n_plus_one_queries { n_plus_one }

    assert_equal 1, notifications.size
    assert_equal 20, notifications.first[:queries].size
  end

  def test_n_plus_one_queries_inside_a_scan
    Prosopite.scan
    Chair.first

    assert_equal 1, Prosopite.n_plus_one_queries { n_plus_one }.size
    Chair.first

    # The queries of the block don't count in the outer scan, which still runs
    assert Prosopite.scan?
    assert_equal [], Prosopite.finish
  end

  def test_assertions_ignore_min_duration_ms
    Prosopite.min_duration_ms = 60_000

    assert_n_plus_one_queries { n_plus_one }
  ensure
    Prosopite.min_duration_ms = nil
  end

  def test_n_plus_one_queries_when_disabled
    Prosopite.enabled = false

    assert_equal 1, Prosopite.n_plus_one_queries { n_plus_one }.size
  ensure
    Prosopite.enabled = true
  end

  private

  def n_plus_one
    Chair.last(20).each do |c|
      c.legs.first
    end
  end
end
