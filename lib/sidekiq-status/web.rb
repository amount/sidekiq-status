# adapted from https://github.com/cryo28/sidekiq_status

module Sidekiq::Status
  # Hook into *Sidekiq::Web* Sinatra app
  module Web
    # Location of Sidekiq::Status::Web view templates
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    # @param [Sidekiq::Web] app
    def self.registered(app)
      app.helpers do
        def sidekiq_status_template(name)
          path = File.join(VIEW_PATH, name.to_s) + ".erb"
          File.open(path).read
        end

        def add_details_to_status(status)
          status['label'] = status_label(status['status'])
          status["pct_complete"] = pct_complete(status)
          return status
        end

        def pct_complete(status)
          return 100 if status['status'] == 'complete'
          Sidekiq::Status::pct_complete(status['jid']) || 0
        end

        def status_label(status)
          case status
          when 'complete'
            'success'
          when 'working'
            'warning'
          when 'queued'
            'primary'
          else
            'danger'
          end
        end
      end

      app.get '/statuses/:jid' do
        job = Sidekiq::Status::get_all params['jid']

        if job.empty?
          status 404
          erb(sidekiq_status_template(:status_not_found))
        else
          @status = OpenStruct.new(add_details_to_status(job))
          erb(sidekiq_status_template(:status))
        end
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.register(Sidekiq::Status::Web)
