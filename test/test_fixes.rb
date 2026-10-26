require 'test_helper'

# Associations that can't be suggested, which never match a query
class Seat < ActiveRecord::Base
  belongs_to :owner, polymorphic: true
  has_many :legs
  has_many :chairs, through: :legs
  has_many :ghosts
end

# Another association to chairs, and a has_and_belongs_to_many, whose join model
# Rails defines as Tag::HABTM_Chairs
class Cushion < ActiveRecord::Base
  belongs_to :chair
end

class Tag < ActiveRecord::Base
  has_and_belongs_to_many :chairs
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

  def test_association_of_the_records_looped_on
    # Cushion#chair runs the same query as Leg#chair, but legs are what's looped on
    notification = Prosopite.n_plus_one_queries { Leg.last(20).each(&:chair) }.first

    assert_equal ['Leg.includes(:chair)'], notification[:fixes]
  end

  def test_too_many_associations_without_their_records
    # On a table that no other test queries, as these models stay in the descendants of
    # Active Record until garbage collection
    4.times do |i|
      Object.const_set("Pillow#{i}", Class.new(ActiveRecord::Base) { belongs_to :cushion })
    end

    assert_equal [], Prosopite::Fixes.for('SELECT "cushions".* FROM "cushions" WHERE "cushions"."id" = ?')
  ensure
    4.times { |i| Object.send(:remove_const, "Pillow#{i}") if Object.const_defined?("Pillow#{i}") }
  end

  def test_queries_that_loading_the_association_does_not_remove
    notifications = Prosopite.n_plus_one_queries do
      Chair.last(20).each { |c| c.legs.where('legs.id > 0').first }
      Chair.last(20).each { |c| c.legs.sum(:id) }
      Chair.last(20).each { |c| Leg.where(chair_id: c.id).first }
    end

    assert_equal 3, notifications.size
    assert_equal [[], [], ['Chair.includes(:legs)', 'Chair.includes(:feet)']], notifications.map { |n| n[:fixes] }
  end

  def test_queries_in_other_forms
    assert_equal ['Chair.includes(:legs)', 'Chair.includes(:feet)'], Prosopite::Fixes.for('SELECT * FROM legs WHERE chair_id = 1')
    assert_equal ['Chair.includes(:legs)', 'Chair.includes(:feet)'],
                 Prosopite::Fixes.for('SELECT `legs`.`id` FROM `legs` WHERE `legs`.`chair_id` IN (1, 2)')
    assert_equal ['Chair.includes(:legs), then legs.size; or a counter cache', 'Chair.includes(:feet), then feet.size; or a counter cache'],
                 Prosopite::Fixes.for('/*application:Shop*/ SELECT COUNT(*) FROM "legs" WHERE "legs"."chair_id" = $1')
    assert_equal [], Prosopite::Fixes.for('SELECT "legs".* FROM "legs" WHERE "chairs"."id" = 1')
    assert_equal [], Prosopite::Fixes.associations('UPDATE "legs" SET "chair_id" = 1')
  end

  def test_no_exists_fix_for_single_records
    assert_equal [], Prosopite::Fixes.for('SELECT 1 AS one FROM "chairs" WHERE "chairs"."id" = ? LIMIT ?')
  end

  def test_no_fixes_from_habtm_join_models
    fixes = Prosopite::Fixes.for('SELECT "chairs".* FROM "chairs" WHERE "chairs"."id" = ?')

    refute fixes.any? { |fix| fix.include?('HABTM') }
    assert Tag.reflect_on_association(:chairs)
  end

  def test_call_stacks_kept_for_records_loaded_after_the_limit
    max_single_callers = Prosopite::MAX_SINGLE_CALLERS
    Prosopite.send(:remove_const, :MAX_SINGLE_CALLERS)
    Prosopite.const_set(:MAX_SINGLE_CALLERS, 1)
    Prosopite.backtrace_cleaner = ActiveSupport::BacktraceCleaner.new

    notification = Prosopite.n_plus_one_queries do
      Leg.first
      chairs = Chair.last(20)
      chairs.each { |c| c.legs.first }
    end.first

    # Its records were loaded after the limit, so without where
    assert_equal ['Chair.includes(:legs)', 'Chair.includes(:feet)'], notification[:fixes]
  ensure
    Prosopite.send(:remove_const, :MAX_SINGLE_CALLERS)
    Prosopite.const_set(:MAX_SINGLE_CALLERS, max_single_callers)
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

    assert_equal ['Cushion.includes(:chair)', 'Leg.includes(:chair)'],
                 Prosopite::Fixes.for('SELECT "chairs".* FROM "chairs" WHERE "chairs"."id" = ?').sort
    assert model.reflect_on_association(:chair)
  end

  def test_models_defined_after_the_index
    query = 'SELECT "legs".* FROM "legs" WHERE "legs"."id" = ?'
    assert_equal [], Prosopite::Fixes.for(query)

    Object.const_set(:Rung, Class.new(ActiveRecord::Base) { belongs_to :leg })

    assert_equal ['Rung.includes(:leg)'], Prosopite::Fixes.for(query)
  ensure
    Object.send(:remove_const, :Rung) if defined?(Rung)
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
