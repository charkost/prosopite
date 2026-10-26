# frozen_string_literal: true

require_relative "lib/prosopite/version"

Gem::Specification.new do |spec|
  spec.name          = "prosopite"
  spec.version       = Prosopite::VERSION
  spec.authors       = ["Mpampis Kostas"]
  spec.email         = ["charkost.rb@gmail.com"]

  spec.summary       = "N+1 auto-detection for Rails with zero false positives / false negatives"
  spec.description   = "N+1 auto-detection for Rails with zero false positives / false negatives"
  spec.homepage      = "https://github.com/charkost/prosopite"
  spec.license       = "Apache-2.0"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/charkost/prosopite"
  spec.metadata["changelog_uri"] = "https://github.com/charkost/prosopite/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) { Dir['lib/**/*', 'README.md', 'CHANGELOG.md', 'LICENSE.txt'].select { |path| File.file?(path) } }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 6.1"
  spec.add_dependency "railties", ">= 6.1"

  spec.add_development_dependency "pry"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "factory_bot"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "minitest-reporters"
end
