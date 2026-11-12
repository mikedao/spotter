# Scoring a capture by hand: the shooter tapped the hole at a pixel of its
# saved after picture; the engine locates the target in that picture (`phase1.py
# pinpoint`: perspective + lens, as for every shot - a round trip on a real shot
# came back within 0.001 mm), returns target mm and the straightened close-ups,
# and the capture becomes a scored shot (Shot#score_by_hand!).
#
#   ShotPinpoint.new(shot).call(912.4, 405.0)   # => the shot, now scored
class ShotPinpoint
  class Failed < StandardError; end

  TIMEOUT = 45

  def initialize(shot) = @shot = shot

  def call(px, py)
    raise Failed, "this capture has no picture to tap" unless @shot.after_image.attached?

    Dir.mktmpdir("pinpoint") do |dir|
      after = save(@shot.after_image, dir, "after.png")
      before = @shot.before_image.attached? ? save(@shot.before_image, dir, "before.png") : nil
      out, err, status = Timeout.timeout(TIMEOUT) do
        Open3.capture3(EngineRunner.python, "phase1.py", "pinpoint", "--target", @shot.practice_session.target,
                       "--image", after, *([ "--before", before ] if before), "--px", px.to_f.to_s, py.to_f.to_s,
                       "--out", dir, chdir: EngineRunner.engine_dir.to_s)
      end
      result = JSON.parse(out.lines.last.to_s) rescue nil
      raise Failed, (err.lines.grep_v(/Warning/).last || "the engine could not read the picture").strip unless status.success? && result
      raise Failed, result["reason"] unless result["found"]

      closeups = %w[ closeup_before closeup_after ].filter_map do |name|
        file = File.join(dir, "#{name}.jpg")
        [ name, File.binread(file) ] if File.exist?(file)
      end.to_h
      @shot.score_by_hand!(x_mm: result["x_mm"], y_mm: result["y_mm"], closeup: result["closeup"], closeups:)
    end
  rescue Timeout::Error
    raise Failed, "locating the target took over #{TIMEOUT} s"
  end

  private
    def save(attachment, dir, name)
      File.join(dir, name).tap { |path| File.binwrite(path, attachment.download) }
    end
end
