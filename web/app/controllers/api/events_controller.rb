# Where the spotter engine reports what it does (contract: docs/engine-events.md).
# Not a browser endpoint: no login, no CSRF. The web app starts the engine for a
# signed-in user (EngineRunner) with that practice session's one-time run token;
# every event must name the session and present its token as a Bearer token, so
# an engine can only ever write into the session it was started for.
module Api
  class EventsController < ActionController::Base
    skip_forgery_protection
    def create
      payload = JSON.parse(params.require(:event))
      session = PracticeSession.find_by(engine_session_id: payload["session_id"].to_s)
      return head :unauthorized unless session && token_matches?(session)

      files = EngineEvent::IMAGES.index_with { params[it] }.compact
      record = EngineEvent.new(payload, files, session:).apply!
      render json: { ok: true, id: record&.id }, status: :created
    rescue JSON::ParserError, EngineEvent::Invalid, ActiveRecord::RecordInvalid => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private
      def token_matches?(session)
        provided = request.authorization.to_s.delete_prefix("Bearer ")
        session.run_token.present? && ActiveSupport::SecurityUtils.secure_compare(provided, session.run_token)
      end
  end
end
