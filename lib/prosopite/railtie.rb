
module Prosopite
  class Railtie < Rails::Railtie
    initializer "prosopite.insert_into_activerecord" do
      ActiveSupport.on_load :active_record do
        setup
      end
    end

    def self.setup
      ActiveRecord::Base.include Prosopite::AnnotatedModel
    end
  end
end
