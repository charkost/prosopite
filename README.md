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

* `Prosopite.min_n_queries`: Minimum number of N queries to report per N+1 case. Defaults to 2.
* `Prosopite.raise = true`: Raise warnings as exceptions. Defaults to `false`.
* `Prosopite.start_raise`: Raises warnings as exceptions from when this is called. Overrides `Proposite.raise`.
* `Propsoite.stop_raise`: Disables raising warnings as exceptions if previously enabled with `Proposite.start_raise`.
* `Prosopite.local_raise?`: Returns `true` if `Prosopite.start_raise` has been called previously.
* `Prosopite.rails_logger = true`: Send warnings to the Rails log. Defaults to `false`.
* `Prosopite.prosopite_logger = true`: Send warnings to `log/prosopite.log`. Defaults to `false`.
* `Prosopite.stderr_logger = true`: Send warnings to STDERR. Defaults to `false`.
* `Prosopite.backtrace_cleaner = my_custom_backtrace_cleaner`: use a different [ActiveSupport::BacktraceCleaner](https://api.rubyonrails.org/classes/ActiveSupport/BacktraceCleaner.html). Defaults to `Rails.backtrace_cleaner`.
* `Prosopite.custom_logger = my_custom_logger`: Set a custom logger. See the following section for the details. Defaults to `false`.
* `Prosopite.enabled = true`: Enables or disables the gem. Defaults to `true`.

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

## Middleware

### Rack

Instead of using an `around_action` hook in a Rails Controller, you can also use the rack middleware instead
implementing auto detect for all controllers.

Add the following line into your `config/initializers/prosopite.rb` file.

```ruby
unless Rails.env.production?
  require 'prosopite/middleware/rack'
  Rails.configuration.middleware.use(Prosopite::Middleware::Rack)
end
```

### Sidekiq
We also provide a middleware for sidekiq `6.5.0+` so that you can auto detect n+1 queries that may occur in a sidekiq job.
You just need to add the following to your sidekiq initializer.

```ruby
Sidekiq.configure_server do |config|
  unless Rails.env.production?
    config.server_middleware do |chain|
      require 'prosopite/middleware/sidekiq'
      chain.add(Prosopite::Middleware::Sidekiq)
    end
  end
end
```

For applications running sidekiq < `6.5.0` but want to add the snippet, you can guard the snippet with something like this and remove it once you upgrade sidekiq:
```ruby
 if Sidekiq::VERSION >= '6.5.0' && (Rails.env.development? || Rails.env.test?)
.....
end
```

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

In block form the `Prosopite.finish` is called automatically for you at the end of the block:

```ruby
Prosopite.scan do
  <code to scan>
end
```

The result of the code block is also returned by `Prosopite.scan`, so you can wrap calls as follows:

```ruby
my_object = Prosopite.scan do
  MyObjectFactory.create(params)
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

Pauses can be ignored with `Prosopite.ignore_pauses = true` in case you want to remember their N+1 queries.

An example of when you might use this is if you are [testing Active Jobs inline](https://guides.rubyonrails.org/testing.html#testing-jobs),
and don't want to run Prosopite on background job code, just foreground app code. In that case you could write an [Active Job callback](https://edgeguides.rubyonrails.org/active_job_basics.html#callbacks) that pauses the scan while the job is running.

## Local Raise

In some cases you may want to configure prosopite to not raise by default and only raise in certain scenarios.
In this example we scan on all controllers but also provide an API to only raise on specific actions.

```ruby
Proposite.raise = false
```

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  def raise_on_n_plus_ones!(**options)
    return if Rails.env.production?

    prepend_around_action(:_raise_on_n_plus_ones, **options)
  end

  unless Rails.env.production?
    around_action :n_plus_one_detection

    def n_plus_one_detection
      ...
    end

    def _raise_on_n_plus_ones
      Proposite.start_raise
      yield
    ensure
      Prosopite.stop_raise
    end
  end
end
```
```ruby
# app/controllers/books_controller.rb
class BooksController < ApplicationController
  raise_on_n_plus_ones!(only: [:index])

  def index
    @books = Book.all.map(&:author) # This will raise N+1 errors
  end

  def show
    @book = Book.find(params[:id])
    @book.reviews.map(&:author) # This will not raise N+1 errors
  end
end

## Custom Logging Configuration

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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/charkost/prosopite.

## License

Prosopite is licensed under the Apache License, Version 2.0. See LICENSE.txt for the full license text.
