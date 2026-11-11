# Applies one event from the spotter engine (contract: docs/engine-events.md at the
# repo root) to the database, then pushes the change to every open range screen.
#
#   EngineEvent.new(payload_hash, files).apply!
#
# Idempotent per shot: the engine's shot id is unique within a session, so a
# retried POST updates instead of duplicating.
class EngineEvent
  class Invalid < StandardError; end

  TYPES = %w[ session_started ready card_off new_card shot unscored session_ended ].freeze
  IMAGES = %w[ before_image after_image closeup_before closeup_after ].freeze

  attr_reader :type, :session_id, :at, :data, :files

  def initialize(payload, files = {})
    @type = payload["type"].to_s
    @session_id = payload["session_id"].to_s
    @at = Time.iso8601(payload["at"].to_s) rescue Time.current
    @data = payload["data"] || {}
    @files = files
    raise Invalid, "unknown event type #{type.inspect}" unless TYPES.include?(type)
    raise Invalid, "session_id is required" if session_id.blank?
  end

  def apply!
    session = find_or_start_session
    record = ActiveRecord::Base.transaction { send("apply_#{type}", session) }
    LiveBroadcast.new(session.reload).call
    record
  end

  private
    def find_or_start_session
      PracticeSession.find_or_create_by!(engine_session_id: session_id) do |s|
        s.started_at = at
        s.target = data["target"].presence || "pistol"
        s.rule = data["rule"]
      end
    end

    def apply_session_started(session)
      session.update!(target: data["target"].presence || session.target, rule: data["rule"] || session.rule,
                      status: "ready")
      session
    end

    def apply_ready(session) = session.tap { it.update!(status: "ready") }
    def apply_card_off(session) = session.tap { it.update!(status: "card_off") }

    def apply_new_card(session)
      session.update!(status: "new_card")
      session.start_new_card!(at:)
    end

    def apply_session_ended(session) = session.tap { it.update!(status: "ended", ended_at: at) }

    def apply_shot(session)
      card = session.card_for_new_shot(at:)
      shot = card.shots.find_or_initialize_by(engine_shot_id: data["engine_shot_id"].presence)
      shot.assign_attributes(
        status: "scored", fired_at: at, number: shot.number || card.next_shot_number,
        trigger: data["trigger"], sound_db: data["sound_db"],
        x_mm: data["x_mm"], y_mm: data["y_mm"], r_mm: data["r_mm"],
        decimal_score: data["decimal"], ring: data["ring"], inner_ten: data["inner_ten"] || false,
        rule: data["rule"], line_mm: data["line_mm"], line_call: data["line_call"] || false,
        ambiguous: data["ambiguous"] || false, overlap: data["overlap"] || false,
        estimates: data["estimates"], region: data["region"], geometry: data["geometry"]
      )
      shot.save!
      attach_images(shot)
      session.update!(status: "shooting")
      shot
    end

    def apply_unscored(session)
      card = session.card_for_new_shot(at:)
      shot = card.shots.create!(status: "unscored", fired_at: at, trigger: data["trigger"],
                                unscored_reason: data["reason"], engine_shot_id: data["engine_shot_id"].presence)
      attach_images(shot)
      shot
    end

    def attach_images(shot)
      IMAGES.each do |name|
        file = files[name]
        shot.public_send(name).attach(file) if file.present?
      end
    end
end
