# adapted from https://github.com/cryo28/sidekiq_status

module Sidekiq::Status
  # Hook into *Sidekiq::Web* Sinatra app
  module Web
    # Location of Sidekiq::Status::Web view templates
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    DEFAULT_PER_PAGE_OPTS = [25, 50, 100].freeze
    DEFAULT_PER_PAGE = 25

    class << self
      def per_page_opts= arr
        @per_page_opts = arr
      end
      def per_page_opts
        @per_page_opts || DEFAULT_PER_PAGE_OPTS
      end
      def default_per_page= val
        @default_per_page = val
      end
      def default_per_page
        @default_per_page || DEFAULT_PER_PAGE
      end
    end

    # @param [Sidekiq::Web] app
    def self.registered(app)

      # Allow method overrides to support RESTful deletes
      app.set :method_override, true

      app.helpers do
        def csrf_tag
          "<input type='hidden' name='authenticity_token' value='#{session[:csrf]}'/>"
        end

        def poll_path
          "?#{request.query_string}" if params[:poll]
        end

        def sidekiq_status_template(name)
          path = File.join(VIEW_PATH, name.to_s) + ".erb"
          File.open(path).read
        end

        def add_details_to_status(status)
          status['label'] = status_label(status['status'])
          status["pct_complete"] ||= pct_complete(status)
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
          when 'working', 'retrying'
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
          halt [404, {"Content-Type" => "text/html"}, [erb(sidekiq_status_template(:status_not_found))]]
        else
          @status = add_details_to_status(job)
          erb(sidekiq_status_template(:status))
        end
      end

      # Retries a failed job from the status list
      app.put '/statuses' do
        job = Sidekiq::RetrySet.new.find_job(params[:jid])
        job ||= Sidekiq::DeadSet.new.find_job(params[:jid])
        job.retry if job
        halt [302, { "Location" => request.referer }, []]
      end

      # Removes a completed job from the status list
      app.delete '/statuses' do
        Sidekiq::Status.delete(params[:jid])
        halt [302, { "Location" => request.referer }, []]
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.register(Sidekiq::Status::Web)
