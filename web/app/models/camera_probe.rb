# Finds the cameras this computer can see, for the Start form's camera picker.
# Runs the engine's `cameras.py --json DIR`, which tries each OpenCV index and
# saves a small preview picture of what each camera sees. The shooter picks by
# PICTURE: macOS's camera names are kept only as a hint, because their order
# usually - not always - matches OpenCV's indices.
#
#   probe = CameraProbe.run!     # ~5 s; not while a session is using the camera
#   probe.cameras                # => [ #<Camera index=0 name_hint="MacBook ...">, ... ]
#   CameraProbe.latest           # the last results, or nil
class CameraProbe
  Camera = Data.define(:index, :width, :height, :brightness, :name_hint, :preview) do
    def value = index.to_s
    def dark? = brightness.to_f < 8
    def label = name_hint.presence || "Camera #{index}"
  end

  class Failed < StandardError; end

  TIMEOUT = 90

  def self.dir = Rails.root.join("tmp", "cameras")
  def self.results_path = dir.join("latest.json")

  def self.latest
    path = results_path
    path.exist? ? new(JSON.parse(path.read), path.mtime) : nil
  end

  def self.run!
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)
    out, err, status = Timeout.timeout(TIMEOUT) do
      Open3.capture3(EngineRunner.python, "cameras.py", "--json", dir.to_s, chdir: EngineRunner.engine_dir.to_s)
    end
    raise Failed, (err.lines.last || "cameras.py failed").strip unless status.success?

    data = JSON.parse(out.lines.last.to_s)
    results_path.write(JSON.generate(data))
    new(data, Time.current)
  rescue Timeout::Error
    raise Failed, "looking for cameras took over #{TIMEOUT} s"
  rescue Errno::ENOENT => e
    raise Failed, "could not run the engine's cameras.py: #{e.message}"
  rescue JSON::ParserError
    raise Failed, "cameras.py did not report any cameras"
  end

  def self.preview_path(index)
    path = dir.join("cam_#{Integer(index)}.jpg")
    path.exist? ? path : nil
  end

  attr_reader :cameras, :found_at

  def initialize(data, found_at)
    @cameras = data.fetch("cameras", []).map do |c|
      Camera.new(index: c["index"], width: c["width"], height: c["height"],
                 brightness: c["brightness"], name_hint: c["name_hint"], preview: c["preview"])
    end
    @found_at = found_at
  end
end
