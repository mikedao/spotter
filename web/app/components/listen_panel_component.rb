# The wizard's sound check: the live meter, the verdict and the way on (Next
# unlocks once a sound would trigger, "camera only" is the escape), then the
# sounds heard - newest first, the last LATEST shown and the rest folded away, so
# the page doesn't grow with every sound. Replaced whole on each sound.
class ListenPanelComponent < ApplicationComponent
  LATEST = 5

  def initialize(state:, user:) = (@state, @user = state, user)

  def running? = @state&.running?
  def data = @state&.data || {}
  def sounds = data["sounds"] || []
  # Judged at the mic's own trigger level (it can change during the check), not
  # the engine's flag, which knows only the engine's default.
  def level = (data["level"] || data["trigger_db"]).to_f.nonzero? || SoundTrigger::DB
  def would_trigger?(sound) = SoundTrigger.would_trigger?(sound["over_db"], sound["len_ms"], level:)
  def shots = sounds.count { would_trigger?(it) }
  def heard_a_shot? = shots.positive?
  def summary = data["summary"]

  def latest_sounds = sounds.last(LATEST).reverse
  def earlier_sounds = sounds[0...-LATEST].to_a.reverse

  # The sounds as a table, each marked whether it would trigger a capture.
  def render_sounds(list, head: true)
    tag.table(class: "w-full max-w-xl table-fixed text-left text-sm tabular-nums") do
      safe_join([
        tag.colgroup(safe_join([ tag.col(class: "w-10"), tag.col, tag.col, tag.col, tag.col(class: "w-32") ])),  # same in both tables
        (tag.thead(tag.tr(safe_join([ tag.th("#", class: "py-1"), tag.th("At"), tag.th("Loudness"), tag.th("Length"), tag.th ])),
                   class: "text-gray-600 dark:text-gray-300") if head),
        tag.tbody(safe_join(list.map { sound_row(it) }), class: "divide-y divide-gray-200 dark:divide-gray-800")
      ].compact)
    end
  end

  private
    def sound_row(s)
      verdict = if would_trigger?(s)
        tag.span("would trigger", class: "rounded bg-green-100 px-2 py-0.5 text-green-900 dark:bg-green-950 dark:text-green-200")
      else
        tag.span(s["over_db"].to_f < level ? "too quiet" : "too short", class: "text-gray-600 dark:text-gray-300")
      end
      tag.tr(safe_join([ tag.td(s["n"], class: "py-1.5"), tag.td(format("%.1f s", s["t"].to_f)), tag.td("+#{s["over_db"].round} dB"),
                         tag.td("#{s["len_ms"]} ms"), tag.td(verdict) ]))
    end
end
