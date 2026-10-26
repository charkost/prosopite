require 'minitest'
require 'prosopite'

module Prosopite
  # Assertions for Minitest, included in Minitest::Test
  module Assertions
    def assert_no_n_plus_one_queries(&block)
      n_plus_one_queries = Prosopite.n_plus_one_queries(&block)
      message = lambda do
        "Expected no N+1 queries, but there were:\n\n" +
          n_plus_one_queries.map { |notification| Prosopite.notification_message(notification) }.join
      end

      assert n_plus_one_queries.empty?, message
    end

    def assert_n_plus_one_queries(&block)
      refute Prosopite.n_plus_one_queries(&block).empty?, 'Expected N+1 queries, but there were none'
    end
  end
end

Minitest::Test.include(Prosopite::Assertions)
