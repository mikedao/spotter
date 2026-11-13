# Writes every shot the shooter has CALLED out as a training example for the
# scoring model (engine/mleval.py measures the rules against them; the model
# will train on them). The folder is a MIRROR of the database: run it after
# every session and it adds the new calls, rewrites changed ones, and removes
# shots that were deleted or un-called since.
#
#   <dir>/index.jsonl                 one label per line (what the eval reads)
#   <dir>/shots/<id>/label.json       the same label
#   <dir>/shots/<id>/before.jpg       straightened close-ups, top-down, at
#   <dir>/shots/<id>/after.jpg        label["closeup"]["px_per_mm"] (20), y UP
#
# A label keeps the rules' PROPOSAL and the shooter's CALL apart, as the shots
# table does. The call's position is only there when the shooter tapped one; a
# ring-only call still says which ring.
#
# The "demo" user's shots are replays of real shots 044-053 (spotter:demo), so
# they are left out unless asked for by LOGIN.
class TrainingExport
  DEMO_USER = "demo"

  Result = Data.define(:dir, :exported, :images_written, :removed, :without_closeups)

  def initialize(dir:, login: nil)
    @dir = Pathname(dir)
    @login = login.presence&.strip&.downcase
  end

  def call
    shots_dir = @dir.join("shots")
    FileUtils.mkdir_p(shots_dir)
    labels = []
    images_written = 0
    without_closeups = 0

    shots.find_each do |shot|
      folder = shots_dir.join(format("%06d", shot.id))
      FileUtils.mkdir_p(folder)
      previous = folder.join("label.json").exist? ? JSON.parse(folder.join("label.json").read)["images"] || {} : {}
      images = {}
      { "before" => shot.closeup_before, "after" => shot.closeup_after }.each do |name, attachment|
        next unless attachment.attached?

        images[name] = { "file" => "#{name}.jpg", "checksum" => attachment.blob.checksum }
        images_written += 1 if write_image(folder.join("#{name}.jpg"), attachment, previous.dig(name, "checksum"))
      end
      without_closeups += 1 unless images.key?("after")
      label = label_for(shot, images)
      File.write(folder.join("label.json"), JSON.pretty_generate(label) + "\n")
      labels << label
    end

    keep = labels.map { format("%06d", it["shot_id"]) }.to_set
    removed = shots_dir.children.select(&:directory?).reject { keep.include?(it.basename.to_s) }
    removed.each { FileUtils.rm_rf(it) }

    tmp = @dir.join("index.jsonl.tmp")
    File.write(tmp, labels.map { JSON.generate(it) + "\n" }.join)
    File.rename(tmp, @dir.join("index.jsonl"))

    Result.new(dir: @dir, exported: labels.size, images_written:, removed: removed.size, without_closeups:)
  end

  def shots
    scope = Shot.where(status: "scored").where.not(called_at: nil)
                .joins(card: { practice_session: :user })
                .includes(card: { practice_session: :user },
                          closeup_before_attachment: :blob, closeup_after_attachment: :blob)
    @login ? scope.where(users: { username: @login }) : scope.where.not(users: { username: DEMO_USER })
  end

  private
    # Pictures don't change once attached, so one is only written when it is new
    # or its blob changed (checked by size and checksum, recorded in the label).
    def write_image(path, attachment, previous_checksum)
      return false if path.exist? && previous_checksum == attachment.blob.checksum && path.size == attachment.blob.byte_size

      File.binwrite(path, attachment.download)
      true
    end

    # What the call says about the shot:
    #   "tapped"    the shooter placed the hole: the position is the label.
    #   "accepted"  no tap, the rules' ring kept: the shooter looked and agreed. The
    #               ring is confirmed; the position only "looked right" (it was not
    #               placed), so it is a weaker label than a tap.
    #   "ring_only" no tap, a different ring: the ring is the only label.
    # Shooters tap mostly when the rules look off, so tapped shots alone overstate
    # the rules' position error.
    def call_kind(shot)
      if shot.call_x_mm && shot.call_y_mm then "tapped"
      elsif shot.call_ring.nil? || shot.call_ring == shot.ring then "accepted"
      else "ring_only"
      end
    end

    def label_for(shot, images)
      session = shot.card.practice_session
      {
        "shot_id" => shot.id,
        "session_id" => session.id,
        "user" => session.user.username,
        "target" => session.target,
        "rule" => shot.rule || session.rule,
        "course" => session.course,
        "stage" => shot.stage,
        "card" => shot.card.number,
        "number" => shot.number,
        "fired_at" => shot.fired_at.utc.iso8601(3),
        "trigger" => shot.trigger,
        # Scored by hand from an unscored capture: the "proposal" is the shooter's
        # own tap, not the rules', so it says nothing about the rules.
        "pinpointed" => shot.pinpointed?,
        "proposal" => {
          "x_mm" => shot.x_mm, "y_mm" => shot.y_mm, "r_mm" => shot.r_mm,
          "decimal" => shot.decimal_score&.to_f, "ring" => shot.ring, "inner_ten" => shot.inner_ten,
          "line_mm" => shot.line_mm, "line_call" => shot.line_call,
          "ambiguous" => shot.ambiguous, "overlap" => shot.overlap
        },
        "call" => {
          "kind" => call_kind(shot),
          "ring" => shot.call_ring, "decimal" => shot.call_decimal&.to_f,
          "x_mm" => shot.call_x_mm, "y_mm" => shot.call_y_mm,
          "note" => shot.call_note, "called_at" => shot.called_at.utc.iso8601(3)
        },
        "estimates" => shot.estimates || {},
        "region" => shot.region || {},
        "geometry" => shot.geometry || {},
        "closeup" => shot.estimates&.dig("closeup"),
        "images" => images
      }
    end
end
