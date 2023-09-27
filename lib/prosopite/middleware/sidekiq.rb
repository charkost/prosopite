module Prosopite
  module Middleware
    class Sidekiq
      include ::Sidekiq::ServerMiddleware
  
      def call(_worker, _msg, _queue)
        Prosopite.scan
        yield
      ensure
        Prosopite.finish
      end
    end
  end  
end
