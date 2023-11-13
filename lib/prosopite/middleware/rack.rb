module Prosopite
  module Middleware
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        Prosopite.scan 
        @app.call(env)
      ensure
        Prosopite.finish
      end
    end
  end
end
