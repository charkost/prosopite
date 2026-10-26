require 'test_helper'

# Like extensions such as prosopite_todo, which filter the notifications
module FilterAllNotifications
  def create_notifications
    super()
    Thread.current[:prosopite_notifications] = {} if Thread.current[:filter_all_notifications]
  end
end
Prosopite.singleton_class.prepend(FilterAllNotifications)

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

  def test_rails_logger
    log = StringIO.new
    previous_logger = Rails.logger
    Rails.logger = Logger.new(log)
    Prosopite.rails_logger = true

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end
    Prosopite.finish

    assert_includes log.string, "\e[91mN+1 queries detected"
  ensure
    Prosopite.rails_logger = nil
    Rails.logger = previous_logger
  end

  def test_rails_log_by_default
    log = StringIO.new
    previous_logger = Rails.logger
    Rails.logger = Logger.new(log)

    Prosopite.scan
    Chair.last(20).each { |c| c.legs.first }
    Prosopite.finish

    assert_includes log.string, 'N+1 queries detected'
  ensure
    Rails.logger = previous_logger
  end

  def test_no_rails_log_by_default_with_another_logger
    log = StringIO.new
    previous_logger = Rails.logger
    Rails.logger = Logger.new(log)
    Prosopite.custom_logger = Logger.new(StringIO.new)

    Prosopite.scan
    Chair.last(20).each { |c| c.legs.first }
    Prosopite.finish

    assert_empty log.string
  ensure
    Rails.logger = previous_logger
    Prosopite.custom_logger = nil
  end

  def test_rails_logger_off
    log = StringIO.new
    previous_logger = Rails.logger
    Rails.logger = Logger.new(log)
    Prosopite.rails_logger = false

    Prosopite.scan
    Chair.last(20).each { |c| c.legs.first }
    Prosopite.finish

    assert_empty log.string
  ensure
    Rails.logger = previous_logger
    Prosopite.rails_logger = nil
  end

  def test_prosopite_logger_with_a_path
    path = File.expand_path('../tmp/logs/n_plus_ones.log', __dir__)
    FileUtils.rm_rf(File.dirname(path))
    Prosopite.prosopite_logger = path

    Prosopite.scan
    Chair.last(20).each { |c| c.legs.first }
    Prosopite.finish

    assert_includes File.read(path), 'N+1 queries detected'
  ensure
    Prosopite.prosopite_logger = nil
    FileUtils.rm_rf(File.dirname(path))
  end

  def test_prosopite_logger_with_a_logger
    log = StringIO.new
    Prosopite.prosopite_logger = Logger.new(log)

    Prosopite.scan
    Chair.last(20).each { |c| c.legs.first }
    Prosopite.finish

    assert_includes log.string, 'N+1 queries detected'
  ensure
    Prosopite.prosopite_logger = nil
  end

  def test_stderr_logger
    Prosopite.stderr_logger = true

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_output(nil, /N\+1 queries detected/) { Prosopite.finish }
  ensure
    Prosopite.stderr_logger = false
  end

  def test_prosopite_logger
    root = Pathname.new(File.expand_path('../tmp/rails_root', __dir__))
    FileUtils.mkdir_p(root.join('log'))
    rails_root = Rails.method(:root)
    Rails.define_singleton_method(:root) { root }
    Prosopite.prosopite_logger = true

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end
    Prosopite.finish

    assert_includes root.join('log', 'prosopite.log').read, 'N+1 queries detected'
  ensure
    Prosopite.prosopite_logger = false
    Rails.define_singleton_method(:root, rails_root)
    FileUtils.rm_rf(root)
  end

  def test_extensions_can_filter_notifications
    Thread.current[:filter_all_notifications] = true
    Prosopite.raise = true

    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_equal [], Prosopite.finish
  ensure
    Thread.current[:filter_all_notifications] = nil
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
