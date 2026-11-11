# Where the spotter engine reports what it does (contract: docs/engine-events.md).
# Not a browser endpoint: no session, no CSRF. Without SPOTTER_TOKEN set, only
# this machine may post (the engine runs beside the web app); with it set, the
# engine must send it as a Bearer token.
module Api
  class EventsController < ActionController::Base
    skip_forgery_protection
    before_action :authenticate_engine

    def create
      payload = JSON.parse(params.require(:event))
      files = EngineEvent::IMAGES.index_with { params[it] }.compact
      record = EngineEvent.new(payload, files).apply!
      render json: { ok: true, id: record&.id }, status: :created
    rescue JSON::ParserError, EngineEvent::Invalid, ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private
      def authenticate_engine
        token = Rails.configuration.x.engine_token
        if token
          provided = request.authorization.to_s.delete_prefix("Bearer ")
          head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(provided, token)
        else
          head :forbidden unless request.local?
        end
      end
  end
end
