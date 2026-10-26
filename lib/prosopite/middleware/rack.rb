require 'json'

module Prosopite
  module Middleware
    class Rack
      FOOTER_STYLE = <<~CSS.freeze
        #prosopite-footer { position: fixed; left: 0; bottom: 0; z-index: 2147483647; box-sizing: border-box;
          max-width: 100vw; max-height: 50vh; overflow: auto; margin: 0; padding: 4px 8px; text-align: left;
          background: #fff5f5; color: #a40000; border: 1px solid #a40000; border-width: 1px 1px 0 0;
          border-top-right-radius: 6px; font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
        #prosopite-footer summary { cursor: pointer; font-weight: bold; }
        #prosopite-footer pre { margin: 4px 0 0; white-space: pre-wrap; font: inherit; color: #222; }
      CSS

      def initialize(app)
        @app = app
      end

      def call(env)
        req = ::Rack::Request.new(env)
        Prosopite.scan("#{req.request_method} #{req.path}")
        status, headers, body = @app.call(env)
        notifications = Prosopite.finish

        if notifications.present? && (Prosopite.add_footer || Prosopite.browser_console) && injectable?(headers, body)
          body = inject(env, headers, body, notifications)
        end

        [status, headers, body]
      ensure
        Prosopite.finish
      end

      private

      # Only buffered bodies can be changed: Rack allows middleware to read a body
      # through to_ary, but not to iterate it, which would break streaming.
      def injectable?(headers, body)
        body.respond_to?(:to_ary) &&
          header(headers, 'content-type').to_s.include?('text/html') &&
          !header(headers, 'content-disposition').to_s.include?('attachment') &&
          header(headers, 'content-encoding').nil? &&
          header(headers, 'transfer-encoding').nil?
      end

      def header(headers, name)
        key = headers.keys.find { |k| k.casecmp?(name) }
        headers[key] if key
      end

      def inject(env, headers, body, notifications)
        parts = body.to_ary
        return body unless parts

        html = String.new(encoding: Encoding::BINARY)
        parts.each { |part| html << part.b }

        index = html.rindex(%r{</body>}i)
        return parts unless index

        html.insert(index, notifications_html(env, notifications).b)

        content_length = headers.keys.find { |k| k.casecmp?('content-length') }
        headers[content_length] = html.bytesize.to_s if content_length

        [html]
      end

      def notifications_html(env, notifications)
        nonce = content_security_policy_nonce(env)
        nonce_attr = nonce ? %( nonce="#{::Rack::Utils.escape_html(nonce)}") : ''
        messages = notifications.map { |notification| Prosopite.notification_message(notification) }

        html = String.new('')
        html << footer_html(messages, nonce_attr) if Prosopite.add_footer
        html << console_html(messages, nonce_attr) if Prosopite.browser_console
        html
      end

      def footer_html(messages, nonce_attr)
        summary = "Prosopite: #{messages.size} N+1 #{messages.size == 1 ? 'query' : 'queries'} detected"

        "<style#{nonce_attr}>#{FOOTER_STYLE}</style>" \
          "<details id=\"prosopite-footer\"><summary>#{summary}</summary>" \
          "<pre>#{::Rack::Utils.escape_html(messages.join)}</pre></details>"
      end

      def console_html(messages, nonce_attr)
        calls = messages.map { |message| "console.warn(#{js_string(message)});" }

        "<script#{nonce_attr}>#{calls.join}</script>"
      end

      # JSON, with the characters that could close the script tag escaped
      def js_string(str)
        JSON.generate(str).gsub(/[<>&  ]/) { |c| format('\\u%04x', c.ord) }
      end

      def content_security_policy_nonce(env)
        return unless env['action_dispatch.content_security_policy_nonce_generator']

        ::ActionDispatch::Request.new(env).content_security_policy_nonce
      end
    end
  end
end
