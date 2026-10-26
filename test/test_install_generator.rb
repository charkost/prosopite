require 'test_helper'
require 'rails/generators/test_case'
require 'generators/prosopite/install_generator'

class TestInstallGenerator < Rails::Generators::TestCase
  tests Prosopite::Generators::InstallGenerator
  destination File.expand_path('../tmp/generator', __dir__)
  setup :prepare_destination

  def test_initializer
    run_generator

    assert_file 'config/initializers/prosopite.rb' do |initializer|
      assert_match(/middleware.use\(Prosopite::Middleware::Rack\)/, initializer)
      assert_match(/Prosopite.raise = true/, initializer)
      refute_match(/pause_during/, initializer)
    end
  end

  def test_initializer_with_factory_bot
    write_file 'Gemfile', "gem 'rails'\ngem 'factory_bot_rails', group: :test\n"

    run_generator

    assert_file 'config/initializers/prosopite.rb', /    Prosopite.pause_during\('factory_bot.run_factory'\)\n  end/
  end

  def test_scans_every_spec
    write_file 'spec/rails_helper.rb', "RSpec.configure do |config|\n  config.use_transactional_fixtures = true\nend\n"

    run_generator

    assert_file 'spec/rails_helper.rb', <<~RUBY
      RSpec.configure do |config|
        config.before { |example| Prosopite.scan(example.location) unless example.metadata[:prosopite] == false }
        config.after { Prosopite.finish }
        config.use_transactional_fixtures = true
      end
    RUBY
  end

  def test_scans_every_spec_of_a_spec_helper
    write_file 'spec/spec_helper.rb', "RSpec.configure do |c|\r\n  c.order = :random\r\nend\r\n"

    run_generator

    assert_file 'spec/spec_helper.rb', /RSpec.configure do \|c\|\r\n  c.before \{ \|example\| Prosopite.scan\(example.location\)/
    assert_file 'spec/spec_helper.rb', /  c.after \{ Prosopite.finish \}\n  c.order = :random/
  end

  def test_spec_helper_without_a_configure_block
    write_file 'spec/rails_helper.rb', "require 'spec_helper'\n"

    output = run_generator

    assert_match(/Scan each spec in spec\/rails_helper.rb/, output)
    assert_file 'spec/rails_helper.rb', "require 'spec_helper'\n"
  end

  def test_scans_every_test
    write_file 'test/test_helper.rb', "require 'rails/test_help'\n"

    run_generator

    assert_file 'test/test_helper.rb', /setup \{ Prosopite.scan\("\#\{self.class\}#\#\{name\}"\) \}\n  teardown \{ Prosopite.finish \}/
  end

  def test_mentions_pg_query_for_postgresql
    write_file 'config/database.yml', "development:\n  adapter: postgresql\n"

    assert_match(/gem 'pg_query'/, run_generator)
  end

  def test_no_pg_query_for_other_databases
    write_file 'config/database.yml', "development:\n  adapter: sqlite3\n"

    refute_match(/pg_query/, run_generator)
  end

  private

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(destination_root, path)))
    File.write(File.join(destination_root, path), content)
  end
end
