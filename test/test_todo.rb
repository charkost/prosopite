require 'test_helper'

class TestTodo < Minitest::Test
  TODO_FILE = File.expand_path('../tmp/prosopite_todo.yml', __dir__)

  def setup
    FileUtils.mkdir_p(File.dirname(TODO_FILE))
    FileUtils.rm_f(TODO_FILE)
    Prosopite.raise = true
    Prosopite.todo_file = TODO_FILE
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.add_silencer { |line| line.include?('/gems/') }
    end

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.raise = nil
    Prosopite.todo_file = nil
    Prosopite.record_todo = nil
    Prosopite.backtrace_cleaner = nil
    FileUtils.rm_f(TODO_FILE)
  end

  def test_record_todo
    Prosopite.record_todo = true

    assert_equal [], scan { legs_n_plus_one }

    entries = YAML.safe_load(File.read(TODO_FILE))
    assert_equal 1, entries.size
    assert_match(/\ASELECT "legs".\* FROM "legs" WHERE "legs"."chair_id" = /, entries.first['query'])
    assert entries.first['location'].end_with?('test/test_todo.rb')
    assert entries.first['fingerprint']
    assert File.read(TODO_FILE).start_with?(Prosopite::TODO_HEADER)
  end

  def test_record_todo_merges_entries
    Prosopite.record_todo = true

    scan { legs_n_plus_one }
    scan { legs_n_plus_one }
    scan { chairs_n_plus_one }

    entries = YAML.safe_load(File.read(TODO_FILE))
    assert_equal 2, entries.size
    assert_equal entries.sort_by { |e| e['fingerprint'] }, entries
  end

  def test_ignore_todo
    Prosopite.record_todo = true
    scan { legs_n_plus_one }
    Prosopite.record_todo = false

    assert_equal [], scan { legs_n_plus_one }
    assert_raises(Prosopite::NPlusOneQueriesError) { scan { chairs_n_plus_one } }
  end

  def test_todo_file_that_does_not_exist
    assert_raises(Prosopite::NPlusOneQueriesError) { scan { legs_n_plus_one } }
  end

  def test_todo_entries_reload_with_the_file
    Prosopite.record_todo = true
    scan { legs_n_plus_one }
    Prosopite.record_todo = false
    assert_equal [], scan { legs_n_plus_one }

    Prosopite.todo_file = "#{TODO_FILE}.missing"
    assert_raises(Prosopite::NPlusOneQueriesError) { scan { legs_n_plus_one } }
  end

  def test_assertions_ignore_the_todo
    Prosopite.record_todo = true

    assert_equal 1, Prosopite.n_plus_one_queries { legs_n_plus_one }.size
    refute File.exist?(TODO_FILE)
  end

  def test_location_without_app_frames
    Prosopite.record_todo = true
    Prosopite.backtrace_cleaner = nil

    scan { legs_n_plus_one }

    assert_nil YAML.safe_load(File.read(TODO_FILE)).first['location']
  end

  private

  def scan(&block)
    Prosopite.scan
    block.call
    Prosopite.finish
  end

  def legs_n_plus_one
    Chair.last(20).each { |c| c.legs.first }
  end

  def chairs_n_plus_one
    Leg.last(20).each(&:chair)
  end
end
