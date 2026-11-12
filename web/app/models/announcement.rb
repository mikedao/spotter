# What the announcer says after an engine event, for the range screen to play in
# the browser (announcer_controller.js). The engine sends it as sentences of
# voice pieces (docs/engine-events.md, "announce"); this leaves out the
# diagnostic sentences unless the shooter turned diagnostic mode on (Settings),
# and pushes it to every open range screen with the URL of each piece in the
# shooter's voice (VoicesController#piece, rendered on first use, then cached).
#
#   Announcement.new(session, data).deliver!
class Announcement
  def initialize(session, data)
    @session = session
    @data = data || {}
  end

  def diagnostic? = @session.user.diagnostic_announcements?
  def kind = diagnostic? ? @data["kind"] : @data["plain_kind"]

  def sentences
    (@data["sentences"] || []).reject { it["diagnostic"] && !diagnostic? }
                              .map { Array(it["pieces"]).map(&:to_s).compact_blank }.reject(&:empty?)
  end

  def playable? = kind.present? && sentences.any?

  # What the browser gets: the tone, the pauses, and each sentence's pieces as
  # [ text, url ] - the text for the browser's own voice when Kokoro isn't set up.
  def payload
    voice = Voice.for(@session.user).id
    gaps = @data["gaps"] || {}
    # kokoro: the voice's files can be played - every piece is in the committed
    # export, or the server can render the missing ones; else the browser's voice.
    playable = Voice.available? || sentences.flatten.all? { Voice.exported_path(voice, it).exist? }
    { kind:, kokoro: playable,
      gaps: { sentence: gaps["sentence"] || 0.55, comma: gaps["comma"] || 0.25 },
      sentences: sentences.map { |pieces| pieces.map { [ it, Voice.piece_url(voice, it) ] } } }
  end

  def deliver!
    return unless playable?

    html = ApplicationController.helpers.tag.div("", data: { controller: "announcement", announcement_payload_value: payload.to_json })
    Turbo::StreamsChannel.broadcast_append_to(@session, target: "announcements", html:)
  end
end
