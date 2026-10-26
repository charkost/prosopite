require 'prosopite'

# expect { ... }.not_to have_n_plus_one_queries
RSpec::Matchers.define :have_n_plus_one_queries do
  supports_block_expectations

  match do |block|
    @n_plus_one_queries = Prosopite.n_plus_one_queries(&block)
    @n_plus_one_queries.any?
  end

  failure_message do
    'expected N+1 queries, but there were none'
  end

  failure_message_when_negated do
    "expected no N+1 queries, but there were:\n\n" +
      @n_plus_one_queries.map { |notification| Prosopite.notification_message(notification) }.join
  end
end
