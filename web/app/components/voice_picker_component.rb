# Rig setup's announcer voice picker: every Kokoro voice with a play button (its
# sample: a normal shot, a flagged one, the end of a card, "ready") and a choice.
# The chosen voice is saved on the user and used from their next session.
class VoicePickerComponent < ApplicationComponent
  def initialize(user:)
    @user = user
  end

  def chosen = Voice.for(@user)
  def available? = Voice.available?
  def groups = Voice.all.group_by(&:accent)
end
