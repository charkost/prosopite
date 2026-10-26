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

  def test_pause_in_child_fiber_pauses_the_scan
    Prosopite.scan
    paused = Fiber.new { Prosopite.pause { Fiber.yield } }
    paused.resume

    Chair.last(20).each do |c|
      c.legs.first
    end
    paused.resume

    assert_no_n_plus_ones
  end

  def test_pause_block_covers_fibers_resumed_in_it
    enum = Enumerator.new do |yielder|
      Chair.last(20).each do |c|
        yielder << c.legs.first
      end
    end

    Prosopite.scan
    enum.next
    Prosopite.pause { 4.times { enum.next } }

    assert_no_n_plus_ones
  end

  def test_enumerator_fibers_are_scanned
    enum = Enumerator.new do |yielder|
      Chair.last(20).each do |c|
        yielder << c.legs.first
      end
    end

    Prosopite.scan
    5.times { enum.next }

    assert_n_plus_one
  end

  def test_finish_while_another_fiber_holds_a_pause
    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end
    paused = Fiber.new { Prosopite.pause { Fiber.yield } }
    paused.resume

    assert_n_plus_one
    paused.resume

    # The next scan starts afresh, instead of continuing the one above
    Prosopite.scan
    Chair.first
    assert_no_n_plus_ones
  end

  def test_scan_of_its_own_in_child_fiber
    Prosopite.scan
    job = Fiber.new do
      Prosopite.scan('job')
      Fiber.yield
      Chair.last(20).each do |c|
        c.legs.first
      end
      Prosopite.finish
    end
    job.resume
    Prosopite.finish

    error = assert_raises(Prosopite::NPlusOneQueriesError) { job.resume }
    assert_match(/Context:\n  job\n/, error.message)
  end

  def test_scans_of_child_fibers_not_part_of_the_parent_scan
    Prosopite.scan
    2.times do
      Fiber.new { Prosopite.scan { Chair.first } }.resume
    end

    assert_no_n_plus_ones
  end

  def test_pause_handed_over_to_threads_like_action_controller_live
    Prosopite.scan

    Prosopite.pause do
      locals = Thread.current.keys.map { |key| [key, Thread.current[key]] }
      Thread.new do
        locals.each { |key, value| Thread.current[key] = value }
        run_n_plus_one_without_database
      end.join
    end

    assert_no_n_plus_ones
  end

  def test_pause_in_thread_like_action_controller_live_ends_with_its_scan
    requests = Queue.new
    results = Queue.new
    # Like a thread of the pool of ActionController::Live, serving two requests
    live_thread = Thread.new do
      2.times do
        locals, code = requests.pop
        locals.each { |key, value| Thread.current[key] = value }
        code.call
        locals.each { |key, _| Thread.current[key] = nil }
        results << :done
      end
    end

    Prosopite.scan
    requests << [Thread.current.keys.map { |key| [key, Thread.current[key]] }, -> { Prosopite.pause }]
    results.pop
    Prosopite.finish

    Prosopite.scan
    requests << [Thread.current.keys.map { |key| [key, Thread.current[key]] }, -> { run_n_plus_one_without_database }]
    results.pop
    live_thread.join

    assert_n_plus_one
  end

  def test_finish_while_a_thread_like_action_controller_live_holds_a_pause
    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    paused = Queue.new
    resume = Queue.new
    locals = Thread.current.keys.map { |key| [key, Thread.current[key]] }
    live_thread = Thread.new do
      locals.each { |key, value| Thread.current[key] = value }
      Prosopite.pause do
        paused << true
        resume.pop
      end
    end
    paused.pop

    assert_n_plus_one
    resume << true
    live_thread.join

    Prosopite.scan
    Chair.first
    assert_no_n_plus_ones
  end

  def test_finish_empties_the_state
    Prosopite.raise = false
    Prosopite.scan
    state = Thread.current[:prosopite_state]
    Chair.last(20).each do |c|
      c.legs.first
    end
    Prosopite.finish

    assert_nil state[:thread]
    assert_empty state[:prosopite_query_holder]
    assert_empty state[:prosopite_query_caller]
    assert_empty state[:prosopite_query_counter]
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

class TestWithoutFiberStorage < Minitest::Test
  def setup
    @fiber_storage = Prosopite::FIBER_STORAGE
    Prosopite.send(:remove_const, :FIBER_STORAGE)
    Prosopite.const_set(:FIBER_STORAGE, false)
    Prosopite.raise = true

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.send(:remove_const, :FIBER_STORAGE)
    Prosopite.const_set(:FIBER_STORAGE, @fiber_storage)
    Prosopite.raise = nil
  end

  def test_n_plus_one
    Prosopite.scan
    Chair.last(20).each do |c|
      c.legs.first
    end

    assert_raises(Prosopite::NPlusOneQueriesError) { Prosopite.finish }
    refute Prosopite.scan?
  end

  def test_child_fibers_not_scanned
    Prosopite.scan
    Fiber.new do
      Chair.last(20).each do |c|
        c.legs.first
      end
    end.resume

    Prosopite.finish
  end

  def test_pause_and_resume
    Prosopite.scan
    Prosopite.pause
    Chair.last(20).each do |c|
      c.legs.first
    end
    Prosopite.resume

    assert Prosopite.scan?
    Prosopite.finish
  end
end
