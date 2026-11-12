# The live camera check: runs the engine's `locate --json --watch` on the chosen
# camera, which re-checks about once a second, and shows each result as it comes
# - the camera's view with the fitted rings, a sharpness number for focusing,
# and plain verdicts - so the shooter can aim and focus while watching them
# change. The latest result is also saved, so a reload shows it.
#
#   RigCheck::Locate.start!(user:, camera: "1", target: "pistol")
#   RigCheck::Locate.latest(user)   # => RigCheck::CameraVerdict
class RigCheck::Locate < RigCheck::LiveProcess
  SECONDS = 120

  class << self
    def label = "camera check"
    def dir = Rails.root.join("tmp", "setup")
    def overlay_path(user) = dir.join("locate-#{user.id}.png")
    def result_path(user) = dir.join("locate-#{user.id}.json")

    # Forget the last result, so a new check starts from "not ready".
    def clear!(user) = [ result_path(user), overlay_path(user) ].each { FileUtils.rm_f(it) }

    def latest(user)
      path = result_path(user)
      path.exist? ? RigCheck::CameraVerdict.new(JSON.parse(path.read), path.mtime) : nil
    end

    def command(user:, camera:, target:, seconds: SECONDS)
      raise EngineRunner::BadCamera, "that isn't a camera number or a stream URL" unless EngineRunner.valid_camera?(camera)
      raise ArgumentError, "unknown target #{target}" unless TargetSpec::SPECS.key?(target)

      FileUtils.mkdir_p(dir)
      [ EngineRunner.python, "phase1.py", "locate", "--json", "--watch", seconds.to_i.clamp(5, 600).to_s,
        "--target", target, "--device", camera, "--overlay", overlay_path(user).to_s ]
    end

    def initial_data(camera:, target:, **) = { "camera" => camera, "target" => target, "seconds" => SECONDS }

    def apply(state, event, user)
      case event["type"]
      when "result"
        state.data.merge!("remaining" => event["remaining"], "seq" => event["seq"])
        result_path(user).write(JSON.generate(event.merge("camera" => state.data["camera"])))
      when "error" then state.error = event["message"]
      when "end" then state.data["ended"] = true
      end
    end

    def finished_cleanly?(state) = state.data["ended"]

    def broadcast(user, state, _event)
      push(user, "locate_panel", LocatePanelComponent.new(state:, latest: latest(user)))
    end
  end
end
