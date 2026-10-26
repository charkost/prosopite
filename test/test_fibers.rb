require 'test_helper'

class TestFibers < Minitest::Test
  def setup
    skip 'Fiber storage needs Ruby 3.2+' unless Prosopite::FIBER_STORAGE

    Prosopite.raise = true

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.raise = nil
  end

  def test_n_plus_one_in_child_fiber
    Prosopite.scan
    Fiber.new do
      Chair.last(20).each do |c|
        c.legs.first
      end
    end.resume

    assert_n_plus_one
  end

  def test_n_plus_one_across_child_fibers
    Prosopite.scan
    Chair.last(20).each do |c|
      Fiber.new { c.legs.first }.resume
    end

    assert_n_plus_one
  end

  def test_scan_not_shared_with_new_threads
    Prosopite.scan

    refute Thread.new { Prosopite.scan? }.value
    assert_no_n_plus_ones_in { Thread.new { run_n_plus_one_without_database }.join }
  end

  def test_scan_handed_over_to_threads_like_action_controller_live
    Prosopite.scan

    # ActionController::Live runs the action in another thread with a copy of these
    locals = Thread.current.keys.map { |key| [key, Thread.current[key]] }
    Thread.new do
      locals.each { |key, value| Thread.current[key] = value }
      run_n_plus_one_without_database
    end.join

    assert_n_plus_one
  end

  def test_scan_not_shared_with_sibling_fibers
    Fiber.new(storage: {}) do
      # A query outside a scan must not leave a scan state for later child fibers to share
      Chair.first

      scanning = Fiber.new do
        Prosopite.scan
        Fiber.yield
        Prosopite.finish
      end
      scanning.resume

      Fiber.new do
        Chair.last(20).each do |c|
          c.legs.first
        end
      end.resume

      scanning.resume
    end.resume
  end

  def test_pause_in_child_fiber
    Prosopite.scan
    paused = Fiber.new { Prosopite.pause { Fiber.yield } }
    paused.resume

    Chair.last(20).each do |c|
      c.legs.first
    end
    paused.resume

    assert_n_plus_one
  end

  def test_overlapping_pauses_in_sibling_fibers
    Prosopite.scan
    first = Fiber.new { Prosopite.pause { Fiber.yield } }
    second = Fiber.new { Prosopite.pause { Fiber.yield } }
    first.resume
    second.resume
    first.resume
    second.resume

    assert Prosopite.scan?

    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  def test_fibers_spawned_while_paused_are_paused
    Prosopite.scan
    Prosopite.pause do
      Fiber.new do
        Chair.last(20).each do |c|
          c.legs.first
        end
      end.resume
    end

    assert_no_n_plus_ones
  end

  def test_child_fiber_cannot_finish_the_scan
    Prosopite.scan
    Fiber.new { Prosopite.finish }.resume

    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_n_plus_one
  end

  private

  # Another thread would get another in-memory SQLite database, without the tables
  def run_n_plus_one_without_database
    connection = ActiveRecord::Base.connection
    2.times do |i|
      ActiveSupport::Notifications.instrument(
        'sql.active_record',
        sql: %(SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = #{i}),
        name: 'Leg Load',
        connection: connection
      )
    end
  end

  def assert_n_plus_one
    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.finish
    end
  end

  def assert_no_n_plus_ones
    Prosopite.finish
  end

  def assert_no_n_plus_ones_in
    yield
    Prosopite.finish
  end
end
