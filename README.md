# Prosopite ![CI](https://github.com/charkost/prosopite/actions/workflows/ci.yml/badge.svg) [![Gem Version](https://badge.fury.io/rb/prosopite.svg)](https://badge.fury.io/rb/prosopite)

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

## Why a new gem

Creating a new gem makes more sense since bullet's core mechanism is completely
different from prosopite's.

## How it works

Prosopite monitors all SQL queries using the Active Support instrumentation
and looks for the following pattern which is present in all N+1 query cases:

More than one queries have the same call stack and the same query fingerprint.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'prosopite'
```

If you're **not** using MySQL/MariaDB, you should also add:

```ruby
gem 'pg_query'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install prosopite

## Configuration

The preferred type of notifications can be configured with:

* `Prosopite.raise = true`: Raise warnings as exceptions
* `Prosopite.rails_logger = true`: Send warnings to the Rails log
* `Prosopite.prosopite_logger = true`: Send warnings to `log/prosopite.log`
* `Prosopite.stderr_logger = true`: Send warnings to STDERR
* `Prosopite.custom_logger = my_custom_logger`:

### Custom Logging Configuration

You can supply a custom logger with the `Prosopite.custom_logger` setting.

This is useful for circumstances where you don't want your logs to be
highlighted with red, or you want logs sent to a custom location.

One common scenario is that you may be generating json logs and sending them to
Datadog, ELK stack, or similar, and don't want to have to remove the default red
escaping data from messages sent to the Rails logger, or want to tag them
differently with your own custom logger.

```ruby
# Turns off logging with red highlights, but still sends them to the Rails logger
Prosopite.custom_logger = Rails.logger
```

```ruby
# Use a completely custom logging instance
Prosopite.custom_logger = MyLoggerClass.new

```

## Development Environment Usage

Prosopite auto-detection can be enabled on all controllers:

```ruby
class ApplicationController < ActionController::Base
  unless Rails.env.production?
    around_action :n_plus_one_detection

    def n_plus_one_detection
      Prosopite.scan
      yield
    ensure
      Prosopite.finish
    end
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

config.before(:each) do
  Prosopite.scan
end

config.after(:each) do
  Prosopite.finish
end
```

WARNING: scan/finish should run before/after **each** test and NOT before/after the whole suite.

## Allow list

Ignore notifications for call stacks containing one or more substrings / regex:

```ruby
Prosopite.allow_stack_paths = ['substring_in_call_stack', /regex/]
```

Ignore notifications matching a specific SQL query:

```ruby
Prosopite.ignore_queries = [/regex_match/, "SELECT * from EXACT_STRING_MATCH"]
```

## Scanning code outside controllers or tests

All you have to do is to wrap the code with:

```ruby
Prosopite.scan
<code to scan>
Prosopite.finish
```

or

```ruby
Prosopite.scan do
<code to scan>
end
```

## Pausing and resuming scans

Scans can be paused:

```ruby
Prosopite.scan
# <code to scan>
Prosopite.pause
# <code that has n+1s>
Prosopite.resume
# <code to scan>
Prosopite.finish
```

You can also pause items in a block, and the `Prosopite.resume` will be done
for you automatically:

```ruby
Prosopite.scan
# <code to scan>

result = Prosopite.pause do
  # <code that has n+1s>
end

Prosopite.finish
```

An example of when you might use this is if you are [testing Active Jobs inline](https://guides.rubyonrails.org/testing.html#testing-jobs),
and don't want to run Prosopite on background job code, just foreground app code. In that case you could write an [Active Job callback](https://edgeguides.rubyonrails.org/active_job_basics.html#callbacks) that pauses the scan while the job is running.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/charkost/prosopite.

## License

Prosopite is licensed under the Apache License, Version 2.0. See LICENSE.txt for the full license text.
