require 'test_helper'
require 'rack/mock'
require 'action_dispatch'
require 'prosopite/middleware/rack'

class TestRackMiddleware < Minitest::Test
  PAGE = '<html><body><h1>Chairs</h1></body></html>'.freeze
  HEADER = Prosopite::Middleware::Rack::HEADER

  def setup
    Prosopite.raise = false

    # 20 chairs, 4 legs each
    chairs = create_list(:chair, 20)
    chairs.each { |c| create_list(:leg, 4, chair: c) }
  end

  def teardown
    Prosopite.raise = nil
    Prosopite.add_footer = nil
    Prosopite.browser_console = nil
  end

  def test_disabled
    Prosopite.enabled = false
    Prosopite.add_footer = true
    scanning = nil

    _, _, body = call_middleware(page: PAGE) do
      scanning = Prosopite.scan?
      Chair.last(20).each { |c| c.legs.first }
    end

    refute scanning
    assert_equal PAGE, body.join
  ensure
    Prosopite.enabled = true
  end

  def test_no_footer_by_default
    _, headers, body = call_middleware(n_plus_one: true)

    assert_equal PAGE, body.join
    assert_nil headers[HEADER]
  end

  def test_footer
    Prosopite.add_footer = true

    _, headers, body = call_middleware(n_plus_one: true)
    html = body.join

    assert_match(
      %r{<details id="prosopite-footer" data-count="1"><summary>Prosopite: 1 N\+1 query detected</summary>},
      html
    )
    assert_includes html, 'SELECT &quot;legs&quot;.* FROM &quot;legs&quot;'
    assert_includes html, 'GET /chairs'
    assert_includes html, '<style>#prosopite-footer'
    assert_includes html, '(true, false);</script>'
    assert html.end_with?('</script></body></html>')
    assert_equal html.bytesize.to_s, headers['content-length']
    assert_nil headers[HEADER]
  end

  def test_footer_without_content_length
    Prosopite.add_footer = true

    _, headers, body = call_middleware(n_plus_one: true, content_length: false)

    assert_includes body.join, 'prosopite-footer'
    assert_nil headers['content-length']
  end

  def test_footer_with_many_n_plus_ones
    Prosopite.add_footer = true

    _, _, body = call_middleware(page: PAGE) do
      Chair.last(20).each { |c| c.legs.first }
      Leg.last(20).each { |l| l.chair }
    end

    assert_includes body.join, '<summary>Prosopite: 2 N+1 queries detected</summary>'
  end

  def test_script_for_requests_on_pages_without_n_plus_ones
    Prosopite.add_footer = true

    _, headers, body = call_middleware(n_plus_one: false)
    html = body.join

    refute_includes html, '<details'
    assert_includes html, 'window.prosopite'
    assert_nil headers[HEADER]
  end

  def test_header_for_responses_that_are_not_pages
    Prosopite.add_footer = true

    _, headers, body = call_middleware(n_plus_one: true, content_type: 'application/json', page: '{"a":1}')

    assert_equal '{"a":1}', body.join
    header = JSON.parse(headers[HEADER])
    assert_equal 1, header['count']
    assert_match(/\AN\+1 queries detected/, header['messages'].first)
  end

  def test_header_for_pages_without_a_body_tag
    Prosopite.add_footer = true

    _, headers, body = call_middleware(n_plus_one: true, page: '<h1>Chairs</h1>')

    assert_equal '<h1>Chairs</h1>', body.join
    assert_equal 1, JSON.parse(headers[HEADER])['count']
  end

  def test_header_for_turbo_frames
    Prosopite.add_footer = true

    env = Rack::MockRequest.env_for('/chairs', 'HTTP_TURBO_FRAME' => 'chairs')
    _, headers, body = call_middleware(n_plus_one: true, env: env)

    assert_equal PAGE, body.join
    assert_equal 1, JSON.parse(headers[HEADER])['count']
  end

  def test_header_size_limit
    Prosopite.add_footer = true

    _, headers, = call_middleware(content_type: 'application/json', page: '{}') do
      30.times do |i|
        # A location of its own for each N+1
        eval("Chair.last(20).each { |c| c.legs.where(id: #{i}).first }", binding, "n_plus_one_#{i}.rb")
      end
    end

    header = JSON.parse(headers[HEADER])
    assert_operator headers[HEADER].bytesize, :<=, Prosopite::Middleware::Rack::HEADER_LIMIT
    assert_equal 30, header['count']
    assert_operator header['messages'].size, :<, 30
    assert header['messages'].all? { |message| message.size <= Prosopite::Middleware::Rack::HEADER_MESSAGE_LIMIT + 5 }
  end

  def test_header_is_ascii
    Prosopite.add_footer = true

    _, headers, = call_middleware(content_type: 'application/json', page: '{}') do
      2.times { Chair.where("name = 'Γιώργος'").first }
    end

    assert headers[HEADER].ascii_only?
    assert_includes JSON.parse(headers[HEADER])['messages'].first, 'Γιώργος'
  end

  def test_footer_skips_streaming_bodies
    Prosopite.add_footer = true

    streaming_body = Object.new
    def streaming_body.each
      raise 'the middleware must not iterate the body'
    end

    _, headers, body = call_middleware(n_plus_one: true, body: streaming_body)

    assert_same streaming_body, body
    assert headers[HEADER]
  end

  def test_footer_skips_bodies_without_an_array
    Prosopite.add_footer = true

    # Like the bodies of Rails < 7.1
    rack_body = Object.new
    def rack_body.to_ary
      nil
    end

    def rack_body.each
      raise 'the middleware must not iterate the body'
    end

    _, _, body = call_middleware(n_plus_one: true, body: rack_body)

    assert_same rack_body, body
  end

  def test_footer_skips_chunked_bodies
    Prosopite.add_footer = true

    _, _, body = call_middleware(n_plus_one: true, headers: { 'transfer-encoding' => 'chunked' })

    assert_equal PAGE, body.join
  end

  def test_browser_console
    Prosopite.browser_console = true

    _, _, body = call_middleware(n_plus_one: true)
    html = body.join

    assert_match(%r{<script>console\.warn\("N\+1 queries detected}, html)
    assert_includes html, '(false, true);</script>'
    refute_includes html, 'prosopite-footer {'
    refute_includes html, '<details'
  end

  def test_browser_console_escapes_script_tags
    Prosopite.browser_console = true

    _, _, body = call_middleware(page: PAGE) do
      2.times { Chair.where(name: '</script><script>alert(1)').first }
    end
    script = body.join[%r{<script>.*</script>}m]

    assert_equal 1, script.scan('</script>').size
    assert_includes script, '</script>'
  end

  def test_content_security_policy_nonce
    Prosopite.add_footer = true
    Prosopite.browser_console = true

    env = Rack::MockRequest.env_for('/chairs')
    env['action_dispatch.content_security_policy_nonce_generator'] = ->(_request) { 'r4nd0m' }
    _, _, body = call_middleware(n_plus_one: true, env: env)
    html = body.join

    assert_includes html, '<style nonce="r4nd0m">'
    assert_includes html, '<script nonce="r4nd0m">'
  end

  def test_raises_before_injecting
    Prosopite.raise = true
    Prosopite.add_footer = true

    assert_raises(Prosopite::NPlusOneQueriesError) { call_middleware(n_plus_one: true) }
  end

  private

  def call_middleware(n_plus_one: true, content_type: 'text/html; charset=utf-8', page: PAGE, body: [page],
                      headers: {}, content_length: true, env: Rack::MockRequest.env_for('/chairs'), &block)
    block ||= lambda do
      Chair.last(20).each { |c| n_plus_one ? c.legs.first : c.name }
    end

    app = lambda do |_env|
      block.call
      response_headers = { 'content-type' => content_type }
      response_headers['content-length'] = page.bytesize.to_s if content_length
      [200, response_headers.merge(headers), body]
    end

    Prosopite::Middleware::Rack.new(app).call(env)
  end
end
