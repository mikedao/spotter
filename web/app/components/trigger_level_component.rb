# The sound check's trigger level for the microphone being checked (SoundTrigger:
# per mic, 2026-11-13 - the laptop's browser heard some shots at +58..+62 dB, under
# the fixed +62). Saved as it changes (trigger_level_controller.js); the browser's
# check re-judges its sounds at once, a check on the server from then on. Every
# session with this mic uses it.
class TriggerLevelComponent < ApplicationComponent
  def initialize(user:, mic:) = (@user, @mic = user, mic)

  def call
    tag.div(class: "mb-4 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm",
            data: { controller: "trigger-level", trigger_level_url_value: helpers.setup_trigger_level_path }) do
      safe_join([
        tag.label("Trigger level", for: "trigger_level", class: "font-medium"),
        tag.input(id: "trigger_level", type: "number", value: SoundTrigger.level(@user, @mic).round,
                  min: SoundTrigger::LEVELS.min.round, max: SoundTrigger::LEVELS.max.round, step: 1,
                  class: "#{TextFieldComponent::INPUT.sub("block w-full", "w-20")} tabular-nums", data: { trigger_level_target: "input", action: "change->trigger-level#save" }),
        tag.span("dB over the room", class: "text-gray-600 dark:text-gray-300"),
        tag.span(data: { trigger_level_target: "status" }, class: "text-gray-500 dark:text-gray-400"),
        tag.p("Set it just under your quietest shot: anything quieter is ignored. Lower catches more, and lets more " \
              "non-shots in (harmless - no new hole, nothing scored).", class: "basis-full text-gray-600 dark:text-gray-300")
      ])
    end
  end
end
