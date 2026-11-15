# The announcer voice picker (Settings): every Kokoro voice with a play button (its
# sample: a normal shot, a flagged one, the end of a card, "ready") and a choice.
# The chosen voice is saved on the user and used from their next session.
class VoicePickerComponent < ApplicationComponent
  def initialize(user:)
    @user = user
  end

  def chosen = Voice.find(@user.voice) || Voice.find(Voice::DEFAULT)   # the voice for "no personality"
  def personalities = Personality.all
  def chosen_personality = Personality.find(@user.personality)
  def voice_name(personality) = Voice.find(personality.voice)&.name
  def ready?(personality) = Personality.ready?(personality.id)
  # Its process's progress rendering its likely lines ({ "prepared", "of" }), or nil.
  def available? = Voice.available?
  def groups = Voice.all.group_by(&:accent)

  # Chatty mode's lines: built into a few voices (in git); in the others they are
  # made the first time each is said, unless prepared ahead (VoicesController#prepare).
  def chatty_pieces = @chatty_pieces ||= Commentary.pieces(@user)
  def built_in?(voice) = (@built_in ||= Voice.all.to_h { [ it.id, Voice.chatty_built_in?(it.id, chatty_pieces) ] })[voice.id]
  def built_in_names = Voice.all.select { built_in?(it) }.map(&:name)
  def readiness = @readiness ||= Voice.chatty_readiness(chosen.id, chatty_pieces)
  def preparing? = Voice.preparing?(chosen.id)
end
