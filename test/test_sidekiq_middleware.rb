require 'test_helper'
require 'sidekiq'
require 'prosopite/middleware/sidekiq'

class TestSidekiqMiddleware < Minitest::Test
  class ChairsJob; end

  def setup
    Prosopite.raise = true

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.raise = nil
  end

  def test_n_plus_one_in_job
    error = assert_raises(Prosopite::NPlusOneQueriesError) do
      call_middleware do
        Chair.last(20).each do |c|
          c.legs.first
        end
      end
    end

    assert_match(/Context:\n  TestSidekiqMiddleware::ChairsJob JID-abc123 queue=default\n/, error.message)
  end

  def test_no_n_plus_ones_in_job
    result = call_middleware { Chair.last(20).map(&:name) }

    assert_equal 20, result.size
    refute Prosopite.scan?
  end

  private

  def call_middleware(&block)
    Prosopite::Middleware::Sidekiq.new.call(ChairsJob.new, { 'jid' => 'abc123' }, 'default', &block)
  end
end
