# Prosopite ![Prosopite](https://raw.githubusercontent.com/charkost/prosopite/icon/icon.png)

Prosopite is able to auto-detect Rails N+1 queries with zero false positives / false negatives.

```
N+1 queries detected:
  SELECT `users`.* FROM `users` WHERE `users`.`id` = 20 LIMIT 1
  SELECT `users`.* FROM `users` WHERE `users`.`id` = 21 LIMIT 1
  SELECT `users`.* FROM `users` WHERE `users`.`id` = 22 LIMIT 1
  SELECT `users`.* FROM `users` WHERE `users`.`id` = 23 LIMIT 1
  SELECT `users`.* FROM `users` WHERE `users`.`id` = 24 LIMIT 1
Call stack:
  app/controllers/thank_you_controller.rb:4:in `block in index'
  app/controllers/thank_you_controller.rb:3:in `each'
  app/controllers/thank_you_controller.rb:3:in `index':
  app/controllers/application_controller.rb:8:in `block in <class:ApplicationController>'
```

The need for prosopite emerged after dealing with various false positives / negatives using the
[bullet](https://github.com/flyerhzm/bullet) gem.

## Compared to Bullet

Prosopite can auto-detect the following extra cases of N+1 queries:

#### N+1 queries after record creations (usually in tests)

```ruby
FactoryBot.create_list(:leg, 10)

Leg.last(10).each do |l|
  l.chair
end
```

#### Not triggered by ActiveRecord associations

```ruby
Leg.last(4).each do |l|
  Chair.find(l.chair_id)
end
```

#### First/last/pluck of collection associations

```ruby
Chair.last(20).each do |c|
  c.legs.first
  c.legs.last
  c.legs.pluck(:id)
end
```

#### Changing the ActiveRecord class with #becomes

```ruby
Chair.last(20).map{ |c| c.becomes(ArmChair) }.each do |ac|
  ac.legs.map(&:id)
end
```

#### Mongoid models calling ActiveRecord

```ruby
class Leg::Design
  include Mongoid::Document
  ...
  field :cid, as: :chair_id, type: Integer
  ...
  def chair
    @chair ||= Chair.where(id: chair_id).first!
  end
end

Leg::Design.last(20) do |l|
  l.chair
end
```

## How it works

Prosopite monitors all SQL queries using the Active Support instrumentation
and looks for the following pattern which is present in all N+1 query cases:

More than one queries have the same call stack and the same query fingerprint.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'prosopite'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install prosopite

## Configuration

The preferred type of notifications can be configured with:

* `Prosopite.rails_logger = true`: Send warnings to the Rails log
* `Prosopite.prosopite_logger = true`: Send warnings to `log/prosopite.log`
* `Prosopite.stderr_logger = true`: Send warnings to STDERR
* `Prosopite.raise = true`: Raise warnings as exceptions

## Development Environment Usage

Prosopite auto-detection can be enabled on all controllers:

```ruby
class ApplicationController < ActionController::Base
  before_action do
    Prosopite.scan
  end

  after_action do
    Prosopite.finish
  end
end
```
And the preferred notification channel should be configured:

```ruby
# config/environments/development.rb

config.after_initialize do
  Prosopite.rails_logger = true
end
```

## Test Environment Usage

Tests with N+1 queries can be configured to fail with:

```ruby
# config/environments/test.rb

config.after_initialize do
  Prosopite.rails_logger = true
  Prosopite.raise = true
end
```

And each test can be scanned with:

```ruby
# spec/spec_helper.rb

config.before do
  Prosopite.scan
end

config.after do
  Prosopite.finish
end
```

## Whitelisting

Ignore notifications for call stacks containing one or more substrings:

```ruby
Prosopite.whitelist = ['substring_in_call_stack']
```

## Scanning code outside controllers or tests

All you have to do is to wrap the code with:

```ruby
Prosopite.scan
<code to scan>
Prosopite.finish
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/charkost/prosopite.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
