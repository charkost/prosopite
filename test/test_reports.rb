require 'test_helper'

class TestReports < Minitest::Test
  JSON_REPORT = File.expand_path('../tmp/prosopite.jsonl', __dir__)

  def setup
    FileUtils.mkdir_p(File.dirname(JSON_REPORT))
    FileUtils.rm_f(JSON_REPORT)
    Prosopite.raise = false

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.github_annotations = nil
    Prosopite.json_report = nil
    Prosopite.backtrace_cleaner = nil
    Prosopite.instance_variable_set(:@github_annotated, nil)
    FileUtils.rm_f(JSON_REPORT)
  end

  def test_github_annotations
    Prosopite.github_annotations = true
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.add_silencer { |line| line.include?('/gems/') }
    end

    out, = capture_io do
      scan { legs_n_plus_one }
      scan { legs_n_plus_one }
    end

    annotations = out.lines
    assert_equal 1, annotations.size
    assert_match(
      %r{\A::warning file=.*test/test_reports.rb,line=\d+,title=N\+1 queries detected::N\+1 queries detected \(\d+\.\d+ms\):%0A  SELECT "legs"},
      annotations.first
    )
    refute_includes annotations.first.chomp, "\n"
  end

  def test_github_annotations_without_app_frames
    Prosopite.github_annotations = true

    out, = capture_io { scan { legs_n_plus_one } }

    assert out.start_with?('::warning title=N+1 queries detected::N+1 queries detected')
  end

  def test_github_annotations_escape_their_values
    assert_equal 'a%25b%0Dc%0Ad', Prosopite.send(:escape_github, "a%b\rc\nd")
  end

  def test_json_report
    Prosopite.json_report = JSON_REPORT

    scan('GET /chairs') { legs_n_plus_one }
    scan { legs_n_plus_one }

    reports = File.readlines(JSON_REPORT).map { |line| JSON.parse(line) }
    assert_equal 2, reports.size
    assert_equal 20, reports.first['queries'].size
    assert_equal 'GET /chairs', reports.first['context']
    assert_equal %w[queries call_stack duration_ms fixes fingerprint context], reports.first.keys
  end

  private

  def scan(context = nil, &block)
    Prosopite.scan(context)
    block.call
    Prosopite.finish
  end

  def legs_n_plus_one
    Chair.last(20).each { |c| c.legs.first }
  end
end
