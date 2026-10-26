require 'test_helper'

class TestNotifications < Minitest::Test
  def setup
    Prosopite.raise = false

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.raise = nil
    Prosopite.backtrace_cleaner = nil
  end

  def test_finish_returns_notifications
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new

    Prosopite.scan('GET /chairs')
    Chair.last(20).each do |c|
      c.legs.first
    end

    notifications = Prosopite.finish

    assert_equal 1, notifications.size
    notification = notifications.first
    assert_equal 20, notification[:queries].size
    assert notification[:call_stack].any? { |f| f.include?('test_notifications.rb') }
    assert_kind_of Float, notification[:duration_ms]
    assert_equal 'GET /chairs', notification[:context]
  end

  def test_finish_returns_no_notifications_without_n_plus_ones
    Prosopite.scan
    Chair.last(20).each(&:name)

    assert_equal [], Prosopite.finish
  end

  def test_finish_without_scan
    assert_nil Prosopite.finish
  end

  def test_n_plus_one_queries_event
    payloads = []
    subscriber = ActiveSupport::Notifications.subscribe('n_plus_one_queries.prosopite') do |event|
      payloads << event.payload
    end

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end
    notifications = Prosopite.finish

    assert_equal notifications, payloads
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def test_n_plus_one_queries_event_before_raising
    Prosopite.raise = true
    payloads = []
    subscriber = ActiveSupport::Notifications.subscribe('n_plus_one_queries.prosopite') do |event|
      payloads << event.payload
    end

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_raises(Prosopite::NPlusOneQueriesError) { Prosopite.finish }
    assert_equal 1, payloads.size
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
