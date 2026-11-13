# Applies one event from the spotter engine (contract: docs/engine-events.md at the
# repo root) to the database, then pushes the change to every open range screen.
#
#   EngineEvent.new(payload_hash, files, session:).apply!
#
# The session exists already: the web app creates it when the user presses Start
# (EngineRunner) and the engine reports into it.
#
# Idempotent per shot: the engine's shot id is unique within a session, so a
# retried POST updates instead of duplicating.
class EngineEvent
  class Invalid < StandardError; end

  TYPES = %w[ session_started ready card_off new_card paused shot shot_images unscored session_ended course announce ].freeze
  IMAGES = %w[ before_image after_image closeup_before closeup_after ].freeze

  attr_reader :type, :session_id, :at, :data, :files

  def initialize(payload, files = {}, session: nil)
    @session = session
    @type = payload["type"].to_s
    @session_id = payload["session_id"].to_s
    @at = Time.iso8601(payload["at"].to_s) rescue Time.current
    @data = payload["data"] || {}
    @files = files
    raise Invalid, "unknown event type #{type.inspect}" unless TYPES.include?(type)
    raise Invalid, "session_id is required" if session_id.blank?
  end

  def apply!
    session = @session || PracticeSession.find_by!(engine_session_id: session_id)
    # An announcement changes nothing stored: it is only played on the range screen.
    return session.tap { Announcement.new(it, data).deliver! } if type == "announce"
    # A shot's pictures, sent after it (the engine's picture lane): attached, no
    # broadcast - the range screen doesn't show them, and the shot is already up.
    return attach_shot_images(session) if type == "shot_images"

    record = ActiveRecord::Base.transaction { send("apply_#{type}", session) }
    LiveBroadcast.new(session.reload).call
    Commentary.after_event(session, type:, record:, data:)   # chatty mode: after the engine's own announcement
    record
  end

  private
    def apply_session_started(session)
      session.update!(target: data["target"].presence || session.target, rule: data["rule"] || session.rule,
                      status: "ready")
      session
    end

    def apply_ready(session) = session.tap { it.show_status!("ready") }
    def apply_card_off(session) = session.tap { it.show_status!("card_off") }
    def apply_paused(session) = session.tap { it.show_status!("paused") }

    def apply_new_card(session)
      session.show_status!("new_card")
      session.start_new_card!(at:)
    end

    def apply_session_ended(session) = session.tap { it.update!(status: "ended", ended_at: at) }

    # The range officer's latest call, for the range screen's clock.
    def apply_course(session)
      session.update!(course_state: data.slice("phase", "label", "ends_at", "stage", "shots", "skippable"))
      session
    end

    # A shot the shooter just PLOTTED by hand (a capture the engine couldn't
    # score) may be found by the engine's camera check moments later - the hole
    # was there, only missed at the time. Within TWIN_MM of the plotted one, on
    # the same card, found by the camera (a new shot comes with a sound): the
    # same shot - the engine's measurement replaces the plot, no second shot.
    TWIN_MM = 3.0
    TWIN_WITHIN = 15.minutes

    def apply_shot(session)
      card = session.card_for_new_shot(at:)
      id = data["engine_shot_id"].presence
      shot = card.shots.find_by(engine_shot_id: id) if id
      twin = shot.nil? && plotted_twin(card)
      shot ||= twin || card.shots.new(engine_shot_id: id)
      course = twin ? {} : course_fields(session, shot)   # a twin keeps its place in the order
      shot.assign_attributes(
        engine_shot_id: id, pinpointed_at: (twin ? nil : shot.pinpointed_at),
        status: "scored", fired_at: twin ? shot.fired_at : at, number: shot.number || card.next_shot_number,
        trigger: data["trigger"], sound_db: data["sound_db"], detect_seconds: data["detect_s"],
        x_mm: data["x_mm"], y_mm: data["y_mm"], r_mm: data["r_mm"],
        decimal_score: data["decimal"], ring: data["ring"], inner_ten: data["inner_ten"] || false,
        rule: data["rule"], line_mm: data["line_mm"], line_call: data["line_call"] || false,
        ambiguous: data["ambiguous"] || false, overlap: data["overlap"] || false,
        estimates: data["estimates"], region: data["region"], geometry: data["geometry"],
        **course
      )
      shot.save!
      attach_images(shot)
      session.show_status!("shooting")
      shot
    end

    def plotted_twin(card)
      return if data["trigger"] == "sound" || data["x_mm"].nil?

      card.shots.where(engine_shot_id: nil, status: "scored").where(pinpointed_at: TWIN_WITHIN.ago..)
          .detect { Math.hypot(it.x_mm.to_f - data["x_mm"].to_f, it.y_mm.to_f - data["y_mm"].to_f) <= TWIN_MM }
    end

    # Where the shot fell in a match or final (nil fields in practice). The
    # competition number is the web app's own count (the engine's counts shots
    # the shooter has since deleted); a match's series follows from it.
    def course_fields(session, shot)
      c = data["course"] || {}
      number = c["number"] && (shot.match_number || (session.shots.maximum(:match_number) || 0) + 1)
      series = (number && Shot.series_for(session, number)) || c["series"]
      { stage: c["stage"], series:, match_number: number, penalty: c["penalty"] }
    end

    def apply_unscored(session)
      card = session.card_for_new_shot(at:)
      shot = card.shots.create!(status: "unscored", fired_at: at, trigger: data["trigger"],
                                unscored_reason: data["reason"], engine_shot_id: data["engine_shot_id"].presence)
      attach_images(shot)
      shot
    end

    def attach_shot_images(session)
      shot = session.shots.find_by(engine_shot_id: data["engine_shot_id"].to_s.presence)
      raise Invalid, "no shot #{data["engine_shot_id"].inspect} for these pictures" unless shot

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
