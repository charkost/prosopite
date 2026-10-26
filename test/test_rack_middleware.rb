require 'test_helper'
require 'rack/mock'
require 'action_dispatch'
require 'prosopite/middleware/rack'

class TestRackMiddleware < Minitest::Test
  PAGE = '<html><body><h1>Chairs</h1></body></html>'.freeze

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

  def test_no_footer_by_default
    _, _, body = call_middleware(n_plus_one: true)

    assert_equal PAGE, body.join
  end

  def test_footer
    Prosopite.add_footer = true

    _, headers, body = call_middleware(n_plus_one: true)
    html = body.join

    assert_match(%r{<details id="prosopite-footer"><summary>Prosopite: 1 N\+1 query detected</summary>}, html)
    assert_includes html, 'SELECT &quot;legs&quot;.* FROM &quot;legs&quot;'
    assert_includes html, 'GET /chairs'
    assert html.end_with?('</details></body></html>')
    assert_equal html.bytesize.to_s, headers['content-length']
  end

  def test_footer_without_n_plus_ones
    Prosopite.add_footer = true

    _, _, body = call_middleware(n_plus_one: false)

    assert_equal PAGE, body.join
  end

  def test_footer_only_on_html_pages
    Prosopite.add_footer = true

    _, _, body = call_middleware(n_plus_one: true, content_type: 'application/json', page: '{"a":1}')

    assert_equal '{"a":1}', body.join
  end

  def test_footer_needs_a_body_tag
    Prosopite.add_footer = true

    _, _, body = call_middleware(n_plus_one: true, page: '<h1>Chairs</h1>')

    assert_equal '<h1>Chairs</h1>', body.join
  end

  def test_footer_skips_streaming_bodies
    Prosopite.add_footer = true

    streaming_body = Object.new
    def streaming_body.each
      raise 'the middleware must not iterate the body'
    end

    _, _, body = call_middleware(n_plus_one: true, body: streaming_body)

    assert_same streaming_body, body
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
    refute_includes html, 'prosopite-footer'
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
                      headers: {}, env: Rack::MockRequest.env_for('/chairs'), &block)
    block ||= lambda do
      Chair.last(20).each { |c| n_plus_one ? c.legs.first : c.name }
    end

    app = lambda do |_env|
      block.call
      [200, { 'content-type' => content_type, 'content-length' => page.bytesize.to_s }.merge(headers), body]
    end

    Prosopite::Middleware::Rack.new(app).call(env)
  end
end
