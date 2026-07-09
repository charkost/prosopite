module Prosopite
  module Middleware
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        req = ::Rack::Request.new(env)
        Prosopite.scan("#{req.request_method} #{req.path}")
        @app.call(env)
      ensure
        Prosopite.finish
      end
    end
  end
end
