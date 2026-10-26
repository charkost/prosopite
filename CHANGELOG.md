# Changelog

## Unreleased

- Suggest fixes in notifications, e.g. `Chair.includes(:legs) where the chairs are loaded, at app/views/chairs/index.html.erb:2`, which `Prosopite.suggest_fixes = false` turns off
- Add an RSpec matcher and Minitest assertions, `have_n_plus_one_queries`, `assert_no_n_plus_one_queries` and `assert_n_plus_one_queries`, and `Prosopite.n_plus_one_queries`
- Add a todo file of known N+1 queries to ignore, to adopt Prosopite gradually, with `Prosopite.todo_file` and `Prosopite.record_todo`
- Show the N+1 queries of Turbo frames and streams, and of fetch and XHR requests, in the footer and the browser console
- Add `Prosopite.github_annotations` and `Prosopite.json_report`, for CI
- Add `Prosopite.sample_rate` and `Prosopite.min_duration_ms`, for production
- Add `Prosopite.pause_during(event)`, e.g. to leave out the N+1 queries of FactoryBot factories
- Add a `rails generate prosopite:install` generator
- pg_query is optional with PostgreSQL, which gets the built-in fingerprint without it instead of a LoadError
- N+1 queries go to the Rails log when no logger is set, unless `Prosopite.rails_logger = false`
- `Prosopite.prosopite_logger` takes a path or a logger too, and creates the directory of its file
- Notifications show the call stack last, after the fix suggestions and the context
- `Prosopite.scan` while a scan of the same fiber is paused doesn't replace it anymore, so the pause applies, and assertions keep their scan
- The footer and the console follow the Content Security Policy of Rails too, leaving out a style or a script that it would block
- Pages with the footer or the console keep their encoding, e.g. UTF-8, instead of becoming binary, for middleware that add to them after Prosopite
- `Prosopite.allow_list=`, deprecated since 1.0.6, will be removed in 3.0

## 2.4.0 (2026-10-26)

- Detect N+1 queries in fibers spawned during a scan, e.g. Async tasks, on Ruby 3.2+, unless they start a scan of their own (#105)
- Pauses apply to the whole scan, including those fibers and ActionController::Live actions, and pause blocks can overlap
- `Prosopite.finish` ends a scan even while it's paused, and reports the N+1 queries found before the pause
- Fix N+1 queries that weren't reported when another N+1, elsewhere, had the same query strings, as happens with bind parameters
- Fix a crash when an ActionController::Live action runs queries while its request finishes the scan
- Fix extensions that override `Prosopite.fingerprint(query)`, broken in 2.3.0
- Load `Prosopite::VERSION` with the library
- Faster `ignore_location_paths`, which cost several times the usual overhead per query, and `allow_stack_paths`
- Faster `finish` for N+1 queries with bind parameters, fingerprinting each distinct query once
- The gem contains only the library and its docs
- The state of a scan isn't kept in `Thread.current[:prosopite_query_*]` anymore. `Thread.current[:prosopite_notifications]` still holds the N+1 queries of the last scan.

## 2.3.0 (2026-10-26)

- Show the N+1 queries of a page in a footer and/or the browser console, with `Prosopite.add_footer` and `Prosopite.browser_console` and the Rack middleware, on Rails 7.1+ (#10, #20)
- `Prosopite.finish` returns the N+1 queries, and each one is published as an `n_plus_one_queries.prosopite` event, e.g. for JSON logs (#102, #46)
- `Prosopite.scan` takes a context for the notifications, which the Rack and Sidekiq middlewares set to the request and the job (#103)
- Add `Prosopite.focus_stack_paths` to report only the N+1 queries whose call stack matches, e.g. the app directory (#88)
- Add `Prosopite.ignore_location_paths` to skip stack frames that differ between calls, e.g. sorbet-runtime (#101)
- Add `Prosopite.display_query_count` and `Prosopite.display_max_n_queries` (#74)
- Fingerprint queries with the adapter of the connection that ran them, fixing SQLite (#89), Oracle (#94) and apps with databases of different adapters (#48). `pg_query` is now needed only for PostgreSQL.
- Don't group queries that ran on different databases, e.g. on shards (#96)
- Declare the actual minimum requirements in the gemspec: Ruby 2.7, Active Record and Railties 6.1 (#98, #99)

## 2.2.0 (2026-04-16)

- Add total query time to N+1 notifications

## 2.1.2 (2025-09-19)

- Avoid using `lease_connection`
- Optimise `Prosopite.subscribe` further

## 2.1.1 (2025-07-04)

- Optimise `location_key` computation in `Prosopite.subscribe`

## 2.1.0 (2025-03-03)

- Add `Prosopite.start_raise` / `Prosopite.stop_raise` to raise even when `Prosopite.raise` is off

## 2.0.0 (2025-02-20)

- Fix the connection deprecation warning of newer Rails
- Fix a Ruby 3.4 string warning
- Test on Ruby 3.2 to 3.4

## 1.4.2 (2023-12-14)

- Rack middleware: don't use the block form of scan

## 1.4.1 (2023-09-28)

- Fix the Sidekiq middleware

## 1.4.0 (2023-09-26)

- Add Rack and Sidekiq middlewares
- Add `Prosopite.enabled`
- Support the Trilogy adapter

## 1.3.3 (2023-08-09)

- Speed up the `sql.active_record` subscription

## 1.3.2 (2023-06-09)

- Fix the MySQL fingerprint for `ORDER BY FIELD()`

## 1.3.1 (2023-05-10)

- Fix a false negative when calling the preloader in a loop

## 1.3.0 (2023-02-07)

- Clean call stacks with `Rails.backtrace_cleaner`

## 1.2.2 (2022-11-02)

- Clear thread variables upon finishing

## 1.2.1 (2022-11-01)

- Handle multiple fingerprints from the same location

## 1.2.0 (2022-10-27)

- Add `Prosopite.min_n_queries` and `Prosopite.ignore_pauses`

## 1.1.4 (2022-10-18)

- Make sure a scan has properly started in `scan?`

## 1.1.3 (2022-09-29)

- Revert making `Prosopite.resume` an alias of `Prosopite.scan`

## 1.1.2 (2022-07-14)

- Allow nested `pause` blocks

## 1.1.1 (2022-07-10)

- `Prosopite.scan` returns the result of its block
- `Prosopite.pause` accepts a block

## 1.0.9 (2022-05-16)

- Add `Prosopite.custom_logger`

## 1.0.8 (2022-02-25)

- Allow regexes in `Prosopite.allow_stack_paths`

## 1.0.7 (2022-01-20)

- Make `Prosopite.resume` an alias of `Prosopite.scan`

## 1.0.6 (2021-12-19)

- Add `Prosopite.ignore_queries`
- Rename `allow_list` to `allow_stack_paths`

## 1.0.5 (2021-12-11)

- Fix the allow list growing indefinitely

## 1.0.4 (2021-12-11)

- Add `Prosopite.pause` and `Prosopite.resume`

## 1.0.3 (2021-09-25)

- Allow preloading multiple associations from the same table

## 1.0.2 (2021-09-25)

- Skip Active Record `SCHEMA` queries

## 1.0.1 (2021-04-07)

- Allow `Prosopite.scan` with a block

## 1.0.0 (2021-03-17)

- Require `pg_query` only for non-MySQL databases
