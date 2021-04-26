require 'minitest/autorun'
require 'factory_bot'
require 'active_record'

require 'prosopite'

class Minitest::Test
  include FactoryBot::Syntax::Methods
end

# Activerecord
ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"

ActiveRecord::Schema.define do
  create_table "legs", force: true do |t|
    t.integer "chair_id"
  end
  create_table "chairs", force: true do |t|
    t.string "name"
  end
end

class Leg < ActiveRecord::Base
  belongs_to :chair
end

class Chair < ActiveRecord::Base
  has_many :legs

  validates_uniqueness_of :name
end

class ArmChair < Chair
end

# FactoryBot
FactoryBot.define do
  factory :leg do
    chair
  end

  factory :chair do
    sequence :name do |n|
      "name#{n}"
    end
  end
end
