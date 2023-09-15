module Prosopite
  module Middleware
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        Prosopite.scan { @app.call(env) }
      end
    end
  end
end
