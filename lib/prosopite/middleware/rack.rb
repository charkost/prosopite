require 'json'

module Prosopite
  module Middleware
    class Rack
      # Carries the N+1 queries of responses that aren't pages, e.g. of fetch requests
      HEADER = 'x-prosopite-notifications'
      # Proxies and servers limit the size of all headers, e.g. nginx to 4 KB by default
      HEADER_LIMIT = 2048
      HEADER_MESSAGE_LIMIT = 400

      FOOTER_STYLE = <<~CSS.freeze
        #prosopite-footer { position: fixed; left: 0; bottom: 0; z-index: 2147483647; box-sizing: border-box;
          max-width: 100vw; max-height: 50vh; overflow: auto; margin: 0; padding: 4px 8px; text-align: left;
          background: #fff5f5; color: #a40000; border: 1px solid #a40000; border-width: 1px 1px 0 0;
          border-top-right-radius: 6px; font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
        #prosopite-footer summary { cursor: pointer; font-weight: bold; }
        #prosopite-footer pre { margin: 4px 0 0; white-space: pre-wrap; font: inherit; color: #222; }
      CSS

      # Shows the N+1 queries of the fetch and XHR requests of a page, like the ones of
      # Turbo, from their header. Turbo runs it again on every visit, so it runs once.
      REQUESTS_SCRIPT = <<~JS.freeze
        (function (showFooter, showConsole) {
          if (window.prosopite) return;
          window.prosopite = true;

          function show(value) {
            var data;
            try { data = JSON.parse(value); } catch (e) { return; }

            if (showConsole) data.messages.forEach(function (message) { console.warn(message); });
            if (!showFooter) return;

            var footer = document.getElementById('prosopite-footer');
            if (!footer) {
              footer = document.createElement('details');
              footer.id = 'prosopite-footer';
              footer.appendChild(document.createElement('summary'));
              footer.appendChild(document.createElement('pre'));
              document.body.appendChild(footer);
            }
            var count = Number(footer.getAttribute('data-count') || 0) + data.count;
            footer.setAttribute('data-count', count);
            footer.querySelector('summary').textContent =
              'Prosopite: ' + count + ' N+1 ' + (count === 1 ? 'query' : 'queries') + ' detected';
            footer.querySelector('pre').textContent +=
              data.messages.join('') + (data.count > data.messages.length ? '...\\n\\n' : '');
          }

          var fetch = window.fetch;
          if (fetch) {
            window.fetch = function () {
              return fetch.apply(window, arguments).then(function (response) {
                var value = response.headers.get('#{HEADER}');
                if (value) show(value);
                return response;
              });
            };
          }

          var open = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function () {
            if (!this.prosopite) {
              this.prosopite = true;
              this.addEventListener('load', function () {
                // Reading a header that a cross-origin response doesn't expose logs an error
                if (!/^#{HEADER}:/im.test(this.getAllResponseHeaders())) return;
                show(this.getResponseHeader('#{HEADER}'));
              });
            }
            return open.apply(this, arguments);
          };
        })
      JS

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) if Prosopite.disabled?

        req = ::Rack::Request.new(env)
        Prosopite.scan("#{req.request_method} #{req.path}")
        status, headers, body = @app.call(env)
        notifications = Prosopite.finish || []

        if Prosopite.add_footer || Prosopite.browser_console
          body, page = add_to_page(env, headers, body, notifications)
          headers[HEADER] = header_value(notifications) if !page && notifications.any?
        end

        [status, headers, body]
      ensure
        Prosopite.finish
      end

      private

      # Adds the N+1 queries and the script for later requests to a page. Responses that
      # aren't pages, like the ones of Turbo frames and streams, return false.
      def add_to_page(env, headers, body, notifications)
        return [body, false] if env['HTTP_TURBO_FRAME'] || !injectable?(headers, body)

        parts = body.to_ary
        return [body, false] unless parts

        html = String.new(encoding: Encoding::BINARY)
        parts.each { |part| html << part.b }

        index = html.rindex(%r{</body>}i)
        return [parts, false] unless index

        html.insert(index, page_html(env, headers, notifications).b)
        # In the encoding of the page again, e.g. for middleware that add to it after this one
        html.force_encoding(parts.first.encoding)
        html.force_encoding(Encoding::BINARY) unless html.valid_encoding?

        content_length = headers.keys.find { |k| k.casecmp?('content-length') }
        headers[content_length] = html.bytesize.to_s if content_length

        [[html], true]
      end

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

      def page_html(env, headers, notifications)
        nonce = content_security_policy_nonce(env)
        nonce_attr = nonce ? %( nonce="#{::Rack::Utils.escape_html(nonce)}") : ''
        policy = content_security_policy(env, headers)
        messages = notifications.map { |notification| Prosopite.notification_message(notification) }

        html = String.new('')
        if Prosopite.add_footer
          html << "<style#{nonce_attr}>#{FOOTER_STYLE}</style>" if inline_allowed?(policy, 'style-src', nonce)
          html << footer_html(messages) if messages.any?
        end

        # A blocked script would also be reported
        return html unless inline_allowed?(policy, 'script-src', nonce)

        script = String.new('')
        script << messages.map { |message| "console.warn(#{js_string(message)});" }.join if Prosopite.browser_console
        script << "#{REQUESTS_SCRIPT}(#{!!Prosopite.add_footer}, #{!!Prosopite.browser_console});"
        html << "<script#{nonce_attr}>#{script}</script>"
      end

      # The Content Security Policy that the response will have. Rails adds its own outside
      # this middleware, unless the response has one, so it's built the same way here.
      def content_security_policy(env, headers)
        policy = header(headers, 'content-security-policy')
        rails_policy = env['action_dispatch.content_security_policy']
        return policy if policy || rails_policy.nil? || header(headers, 'content-security-policy-report-only')

        request = ::ActionDispatch::Request.new(env)
        return if request.content_security_policy_report_only

        rails_policy.build(request.controller_instance || request, request.content_security_policy_nonce,
                           request.content_security_policy_nonce_directives)
      end

      # Whether the policy lets an inline element of the directive run, with the nonce if any.
      # Browsers ignore 'unsafe-inline' in directives with nonces, hashes or 'strict-dynamic'.
      def inline_allowed?(policy, directive, nonce)
        return true unless policy

        directives = policy.split(';').map(&:split)
        sources = directives.assoc("#{directive}-elem") || directives.assoc(directive) || directives.assoc('default-src')
        return true unless sources
        return true if nonce && sources.include?("'nonce-#{nonce}'")

        sources.include?("'unsafe-inline'") && sources.none? { |source| source.match?(/\A'(?:nonce-|sha\d+-|strict-dynamic')/) }
      end

      def footer_html(messages)
        summary = "Prosopite: #{messages.size} N+1 #{messages.size == 1 ? 'query' : 'queries'} detected"

        "<details id=\"prosopite-footer\" data-count=\"#{messages.size}\"><summary>#{summary}</summary>" \
          "<pre>#{::Rack::Utils.escape_html(messages.join)}</pre></details>"
      end

      # As many messages as fit, as ASCII JSON, with the count of all the N+1 queries
      def header_value(notifications)
        messages = []
        notifications.each do |notification|
          message = Prosopite.notification_message(notification)
          message = "#{message[0, HEADER_MESSAGE_LIMIT]}...\n\n" if message.size > HEADER_MESSAGE_LIMIT
          break if header_json(notifications.size, messages + [message]).bytesize > HEADER_LIMIT

          messages << message
        end

        header_json(notifications.size, messages)
      end

      def header_json(count, messages)
        JSON.generate({ count: count, messages: messages }, ascii_only: true)
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
