require 'rails/generators'

module Prosopite
  module Generators
    # rails generate prosopite:install
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Creates config/initializers/prosopite.rb and scans every test for N+1 queries'

      def create_initializer
        template 'prosopite.rb', 'config/initializers/prosopite.rb'
      end

      def scan_tests
        if File.exist?(File.join(destination_root, 'spec/rails_helper.rb'))
          inject_into_file 'spec/rails_helper.rb', <<-RUBY, after: "RSpec.configure do |config|\n"
  config.before { |example| Prosopite.scan(example.location) unless example.metadata[:prosopite] == false }
  config.after { Prosopite.finish }
          RUBY
        elsif File.exist?(File.join(destination_root, 'test/test_helper.rb'))
          append_to_file 'test/test_helper.rb', <<~RUBY

            class ActiveSupport::TestCase
              setup { Prosopite.scan("\#{self.class}#\#{name}") }
              teardown { Prosopite.finish }
            end
          RUBY
        end
      end

      def mention_pg_query
        database = File.join(destination_root, 'config/database.yml')
        return unless File.exist?(database) && File.read(database).include?('postgresql')

        say "With PostgreSQL, gem 'pg_query' makes the fingerprints of queries more precise, if it installs on your systems"
      end

      private

      def factory_bot?
        gemfile = File.join(destination_root, 'Gemfile')
        File.exist?(gemfile) && File.read(gemfile).match?(/['"]factory_bot(_rails)?['"]/)
      end
    end
  end
end
