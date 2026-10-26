module Prosopite
  module Middleware
    class Sidekiq
      include ::Sidekiq::ServerMiddleware
  
      def call(worker, msg, queue)
        Prosopite.scan("#{worker.class.name} JID-#{msg['jid']} queue=#{queue}")
        yield
      ensure
        Prosopite.finish
      end
    end
  end  
end
