require_relative 'extension/worker'

module Sidekiq
  class Batch
    module Middleware
      class ClientMiddleware
        include ::Sidekiq::ClientMiddleware
        
        def call(_worker, msg, _queue, _redis_pool = nil)
          if (batch = Thread.current[:batch])
            batch.increment_job_queue(msg['jid']) if (msg[:bid] = batch.bid)
          end
          yield
        end
      end

      class ServerMiddleware
        include ::Sidekiq::ServerMiddleware
        
        def call(_worker, msg, _queue)
          if (bid = msg['bid'])
            begin
              Thread.current[:batch] = Sidekiq::Batch.new(bid)
              yield
              Thread.current[:batch] = nil
              Batch.process_successful_job(bid, msg['jid'])
            rescue
              Batch.process_failed_job(bid, msg['jid'])
              raise
            ensure
              Thread.current[:batch] = nil
            end
          else
            yield
          end
        end
      end

      def self.configure
        Sidekiq.configure_client do |config|
          config.client_middleware do |chain|
            chain.add Sidekiq::Batch::Middleware::ClientMiddleware
          end
        end
        Sidekiq.configure_server do |config|
          config.client_middleware do |chain|
            chain.add Sidekiq::Batch::Middleware::ClientMiddleware
          end
          config.server_middleware do |chain|
            chain.add Sidekiq::Batch::Middleware::ServerMiddleware
          end
        end
        Sidekiq::Worker.send(:include, Sidekiq::Batch::Extension::Worker)
      end
    end
  end
end

Sidekiq::Batch::Middleware.configure
