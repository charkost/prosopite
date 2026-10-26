require 'test_helper'

# Associations that can't be suggested, which never match a query
class Seat < ActiveRecord::Base
  belongs_to :owner, polymorphic: true
  has_many :legs
  has_many :chairs, through: :legs
  has_many :ghosts
end

class TestFixes < Minitest::Test
  def setup
    Prosopite.raise = true

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.raise = nil
    Prosopite.suggest_fixes = nil
  end

  def test_has_many
    error = assert_n_plus_one do
      Chair.last(20).each { |c| c.legs.first }
    end

    assert_match(/Possible fixes:\n  Chair.includes\(:legs\)\n  Chair.includes\(:feet\)\n/, error.message)
  end

  def test_belongs_to
    error = assert_n_plus_one do
      Leg.last(20).each(&:chair)
    end

    assert_match(/Possible fix:\n  Leg.includes\(:chair\)\n/, error.message)
  end

  def test_count
    notification = Prosopite.n_plus_one_queries { Chair.last(20).each { |c| c.legs.count } }.first

    assert_includes notification[:fixes], 'Chair.includes(:legs), then legs.size; or a counter cache'
  end

  def test_exists
    notification = Prosopite.n_plus_one_queries { Chair.last(20).each { |c| c.legs.exists? } }.first

    assert_includes notification[:fixes], 'Chair.includes(:legs), then legs.any?'
  end

  def test_where_the_records_are_loaded
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.add_silencer { |line| line.include?('/gems/') }
    end

    notification = Prosopite.n_plus_one_queries do
      chairs = Chair.last(20); line = __LINE__
      chairs.each { |c| c.legs.first }
      Leg.last(20).each(&:chair)
      @line = line
    end.first

    assert_match(/\AChair.includes\(:legs\) where the chairs are loaded, at .*test_fixes.rb:#{@line}\z/, notification[:fixes].first)
  ensure
    Prosopite.backtrace_cleaner = nil
  end

  def test_records_loaded_before_the_scan
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new
    chairs = Chair.last(20)

    notification = Prosopite.n_plus_one_queries { chairs.each { |c| c.legs.first } }.first

    assert_equal ['Chair.includes(:legs)', 'Chair.includes(:feet)'], notification[:fixes]
  ensure
    Prosopite.backtrace_cleaner = nil
  end

  def test_query_of_no_association
    assert_equal [], Prosopite::Fixes.for('SELECT "legs".* FROM "legs" WHERE "legs"."id" > 1')
    assert_equal [], Prosopite::Fixes.for('SELECT 1')
  end

  def test_anonymous_model
    model = Class.new(ActiveRecord::Base) do
      self.table_name = 'legs'
      belongs_to :chair
    end

    assert_equal ['Leg.includes(:chair)'], Prosopite::Fixes.for('SELECT "chairs".* FROM "chairs" WHERE "chairs"."id" = ?')
    assert model.reflect_on_association(:chair)
  end

  def test_suggest_fixes_off
    Prosopite.suggest_fixes = false

    error = assert_n_plus_one do
      Leg.last(20).each(&:chair)
    end

    refute_match(/Possible fix/, error.message)
  end

  private

  def assert_n_plus_one(&block)
    Prosopite.scan
    block.call
    assert_raises(Prosopite::NPlusOneQueriesError) { Prosopite.finish }
  end
end
