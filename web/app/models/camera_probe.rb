# Finds the cameras and microphones this computer can see, for the Start form.
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

  Mic = Data.define(:name, :channels) do
    def value = name
  end

  # Camera-only: the engine scores from its camera check alone (`--mic none`).
  NO_MIC = "none"

  # The microphone that belongs to a camera: same device name once "camera" /
  # "microphone" are dropped ("Michael's iPhone Camera" ~ "Michael's iPhone
  # Microphone", "Razer Kiyo" ~ "Razer Kiyo").
  def self.pair(camera_name, mics)
    key = ->(n) { n.to_s.downcase.gsub(/\b(camera|microphone|mic)\b/, "").squish }
    want = key.(camera_name)
    return nil if want.empty?

    named = mics.reject { key.(it.name).empty? }   # a bare "Microphone" would match anything
    named.find { key.(it.name) == want } || named.find { key.(it.name).include?(want) || want.include?(key.(it.name)) }
  end

  class Failed < StandardError; end

  TIMEOUT = 90

  # Specs write fake results here and delete them: never the dev server's own.
  def self.dir = Rails.root.join("tmp", Rails.env.test? ? "cameras-test" : "cameras")
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

  attr_reader :cameras, :microphones, :found_at

  def initialize(data, found_at)
    @cameras = data.fetch("cameras", []).map do |c|
      Camera.new(index: c["index"], width: c["width"], height: c["height"],
                 brightness: c["brightness"], name_hint: c["name_hint"], preview: c["preview"])
    end
    @microphones = data.fetch("microphones", []).map { Mic.new(name: it["name"], channels: it["channels"]) }
    @found_at = found_at
  end

  # The mic for each camera, for the Start form to pre-select (camera value => mic name).
  def pairs = cameras.to_h { |c| [ c.value, self.class.pair(c.name_hint, microphones)&.name ] }
end
