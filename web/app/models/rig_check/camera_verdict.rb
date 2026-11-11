# One camera check's measurements (from the engine's `locate --json`), as plain
# verdicts with what to do about them. RigCheck::Locate produces them, live.
class RigCheck::CameraVerdict
  Verdict = Data.define(:level, :label, :text)   # level: :good, :warn, :bad, :info

  attr_reader :data, :checked_at

  def initialize(data, checked_at) = (@data, @checked_at = data, checked_at)

  def found? = data["found"]
  def camera = data["camera"]
  def sharpness = data["sharpness"]
  def seq = data["seq"].to_i

  # Plain-language verdicts, worst first in each group, with what to do about them.
  def verdicts
    return [ Verdict.new(:bad, "Target", "Not found: #{data['reason']}. Check the card is in view and lit.") ] unless found?

    [ focus, rings, flatness, framing, scale, lighting, view ].compact
  end

  def ok? = found? && verdicts.none? { it.level == :bad }

  private
    def focus
      e = data["edge_rms_px"]
      return Verdict.new(:warn, "Focus", "Couldn't measure the black's edge.") unless e

      level = e <= 0.5 ? :good : e <= 1.0 ? :warn : :bad
      text = { good: "Sharp", warn: "A little soft - try adjusting focus", bad: "Blurry - adjust focus or move the camera" }[level]
      Verdict.new(level, "Focus", "#{text} (edge fit #{e} px)")
    end

    def rings
      unless data["perspective"]
        return Verdict.new(:bad, "Ring fit", "The ring lines couldn't be fitted (#{data['perspective_reason']}). Scores would be wrong away from the centre.")
      end

      r = data["ring_rms_mm"]
      level = r <= 0.15 ? :good : r <= 0.25 ? :warn : :bad
      Verdict.new(level, "Ring fit", "#{data['rings']} rings fitted, #{r} mm RMS#{' - usually ~0.1' unless level == :good}")
    end

    def flatness
      f = data["flat_worst_mm"]
      return nil unless f

      ring, angle = data["flat_worst_at"]
      # Real cards read 0.2-0.6 mm and still scored right 29 of 30 shots (line
      # calls are flagged anyway), so only beyond 0.5 mm is it a problem.
      level = f.abs <= 0.15 ? :good : f.abs <= 0.5 ? :warn : :bad
      where = "ring #{ring}, #{TargetSpec.direction(Math.cos(angle * Math::PI / 180), Math.sin(angle * Math::PI / 180))}"
      text = { good: "Flat", warn: "Slightly bowed", bad: "Not flat - mount the card flatter" }[level]
      hint = " - holes in a used card read as bow; judge this on a fresh card" unless level == :good
      Verdict.new(level, "Card flat", "#{text} (worst #{f} mm at #{where})#{hint}")
    end

    def framing
      sides = data["ring1_offscreen"] || []
      return Verdict.new(:good, "Framing", "The whole target is in view") if sides.empty?

      Verdict.new(:bad, "Framing", "Ring 1 runs off the #{sides.to_sentence} of the picture - shots there can't be seen. Re-aim the camera.")
    end

    def scale
      m = data["mm_per_px"]
      level = m <= 0.25 ? :good : m <= 0.32 ? :warn : :bad
      text = { good: "Close enough", warn: "A bit far - move the camera closer if you can", bad: "Too far - the card is small in the picture" }[level]
      Verdict.new(level, "Distance", "#{text} (#{m} mm per pixel)")
    end

    def lighting
      sat, bright = data["saturated_pct"], data["brightness"]
      return Verdict.new(:bad, "Lighting", "Too bright: #{sat}% of the picture is blown out") if sat > 0.5
      return Verdict.new(:warn, "Lighting", "Dark (average #{bright}/255) - more light would help") if bright < 35

      Verdict.new(:good, "Lighting", "OK")
    end

    def view = Verdict.new(:info, "View angle", "About #{data['view_deg'].round}° off to the side - corrected automatically")
end
