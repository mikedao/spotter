# The new-session setup wizard, run every time a session starts, so the camera
# and microphone are known good before the first shot:
#
#   1. camera      look for cameras (CameraProbe), pick the one on the target
#                  by its picture, and the target type
#   2. check       the live camera check (RigCheck::Locate): Next unlocks at
#                  "Ready to shoot"; "continue anyway" is the escape
#   3. microphone  the sound check (RigCheck::Listen): Next unlocks once a sound
#                  would trigger; "no microphone - camera only" is the escape.
#                  Or THIS BROWSER's microphone (the laptop at the firing line):
#                  the check runs in the page (BrowserListenComponent) and
#                  reports a shot it heard to `heard`
#   4. start       shots per card, then Start (PracticeSessionsController#create)
#
# The camera and microphone are remembered on the user (last_camera, last_mic),
# the target in the cookie session. Each step stops the previous step's check,
# so the camera and microphone are free for the next one.
class SessionSetupController < ApplicationController
  before_action :refuse_while_shooting, except: %i[ overlay stop_check stop_listen heard trigger_level ]

  # New session: look for cameras and microphones, then step 1.
  def create
    RigCheck.stop_for!(Current.user)
    CameraProbe.run!
    redirect_to setup_camera_path
  rescue CameraProbe::Failed => e
    redirect_to setup_camera_path, alert: "Couldn't look for cameras: #{e.message}"
  end

  def camera
    RigCheck.stop_for!(Current.user)
    @choice = DeviceChoice.new(user: Current.user)
    @target = target
  end

  def choose_camera
    camera = (params[:camera] == "url" ? params[:camera_url] : params[:camera]).to_s.strip
    raise EngineRunner::BadCamera, "pick a camera" if camera.blank?
    raise EngineRunner::BadCamera, "that isn't a camera number or a stream URL" unless EngineRunner.valid_camera?(camera)
    raise EngineRunner::BadCamera, "pick a target" unless TargetSpec::SPECS.key?(params[:target])

    pair_mic(camera)
    Current.user.update!(last_camera: camera)
    session[:setup_target] = params[:target]
    start_camera_check
    redirect_to setup_check_path
  rescue EngineRunner::BadCamera, RigCheck::Busy => e
    redirect_to setup_camera_path, alert: "#{e.message.upcase_first}."
  end

  def check
    return redirect_to(setup_camera_path) if Current.user.last_camera.blank?

    @camera = Current.user.last_camera
    @state = RigCheck::Locate.state_for(Current.user)
    @latest = RigCheck::Locate.latest(Current.user)
  end

  # Check again (a check runs two minutes, then stops).
  def recheck
    start_camera_check
    redirect_to setup_check_path
  rescue EngineRunner::BadCamera, RigCheck::Busy, ArgumentError => e
    redirect_to setup_check_path, alert: "Camera check: #{e.message}."
  end

  def stop_check
    RigCheck::Locate.stop!(Current.user)
    redirect_to setup_check_path
  end

  def overlay
    path = RigCheck::Locate.overlay_path(Current.user)
    path.exist? ? send_file(path, type: "image/png", disposition: "inline") : head(:not_found)
  end

  # The sound check - skipped when this microphone passed one before and is
  # still connected (?again=1 checks anyway).
  def microphone
    RigCheck::Locate.stop!(Current.user)
    @choice = DeviceChoice.new(user: Current.user)
    @state = RigCheck::Listen.state_for(Current.user)
    remember_sound_check(@state)
    redirect_to setup_start_path if params[:again].blank? && @state.nil? && remembered_mic?(@choice)
  end

  # Listen on the chosen microphone; or, for camera only, straight on to Start;
  # or, for this browser's microphone, back to the step, where the page listens.
  def listen
    mic = params[:mic].to_s.strip
    if mic == CameraProbe::NO_MIC
      Current.user.update!(last_mic: mic)
      return redirect_to(setup_start_path)
    end
    if mic == CameraProbe::BROWSER_MIC
      RigCheck.stop_for!(Current.user)
      Current.user.update!(last_mic: mic)
      return redirect_to(setup_microphone_path(again: 1))
    end

    RigCheck.stop_for!(Current.user)
    RigCheck::Listen.start!(user: Current.user, mic:, seconds: 60, level: SoundTrigger.level(Current.user, mic))
    Current.user.update!(last_mic: mic)
    redirect_to setup_microphone_path
  rescue RigCheck::Busy, EngineRunner::BadCamera => e
    redirect_to setup_microphone_path, alert: "Sound check: #{e.message}."
  end

  def stop_listen
    RigCheck::Listen.stop!(Current.user)
    redirect_to setup_microphone_path
  end

  # The browser's sound check heard a sound that would trigger: remembered like
  # a server-side check, so Start says "heard a shot" and next time skips it.
  def heard
    over_db, len_ms = params[:over_db].to_f, params[:len_ms].to_f
    level = SoundTrigger.level(Current.user, CameraProbe::BROWSER_MIC)
    return head(:unprocessable_content) unless SoundTrigger.would_trigger?(over_db, len_ms, level:)

    Current.user.update!(last_mic: CameraProbe::BROWSER_MIC,
                         sound_check: { "mic" => CameraProbe::BROWSER_MIC, "at" => Time.current.iso8601,
                                        "loudest_db" => over_db.round(1),
                                        "trigger_db" => level, "trigger_ms" => SoundTrigger::MS })
    head :no_content
  end

  # The trigger level for the microphone being checked (SoundTrigger.level): set
  # from the sound check, used by every session with that mic. A check running
  # on the server judges its sounds by it from now on.
  def trigger_level
    mic = Current.user.last_mic.to_s
    return head(:unprocessable_content) if mic.blank? || mic == CameraProbe::NO_MIC

    db = SoundTrigger.set_level!(Current.user, mic, params.require(:db))
    if (state = RigCheck::Listen.set_level(Current.user, db))
      RigCheck::Listen.broadcast(Current.user, state, nil)
    end
    respond_to do |format|
      format.json { render json: { db: } }
      format.html { redirect_to setup_microphone_path(again: 1) }
    end
  end

  def start
    RigCheck.stop_for!(Current.user)
    return redirect_to(setup_camera_path) if Current.user.last_camera.blank?

    @target = TargetSpec::SPECS.fetch(target)
    @camera = Current.user.last_camera
    @mic = Current.user.last_mic.presence || CameraProbe::NO_MIC
    @camera_ok = RigCheck::Locate.latest(Current.user)&.then { it.ok? && it.camera.to_s == @camera }
    listen = RigCheck::Listen.state_for(Current.user)
    remember_sound_check(listen)
    @mic_ok = Current.user.sound_checked?(@mic)
    @mic_checked_at = Current.user.sound_checked_at if @mic_ok
    @gear = GearChoice.new(user: Current.user, target: @target.key)
  end

  private
    def target = session[:setup_target].presence_in(TargetSpec::SPECS.keys) || "pistol"

    # A sound check that heard a shot that would trigger: kept for next time.
    def remember_sound_check(state)
      data = state&.data || {}
      return if data["mic"].blank?

      level = SoundTrigger.level(Current.user, data["mic"])
      heard = (data["sounds"] || []).select { SoundTrigger.would_trigger?(it["over_db"], it["len_ms"], level:) }
      return if heard.empty?

      Current.user.update!(sound_check: { "mic" => data["mic"], "at" => Time.current.iso8601,
                                          "loudest_db" => heard.map { it["over_db"].to_f }.max.round(1),
                                          "trigger_db" => level, "trigger_ms" => SoundTrigger::MS })
    end

    # The microphone the user will shoot with passed a sound check before and is
    # still connected (in the last device search).
    def remembered_mic?(choice)
      mic = Current.user.last_mic
      mic.present? && mic != CameraProbe::NO_MIC && Current.user.sound_checked?(mic) &&
        (mic == CameraProbe::BROWSER_MIC || choice.microphones.map(&:name).include?(mic))
    end

    def refuse_while_shooting
      return unless (running = EngineRunner.running)

      if running.user == Current.user
        redirect_to practice_session_path(running), notice: "Your session is running."
      else
        redirect_to practice_sessions_path, alert: "#{running.user.name} is shooting - one session at a time on this rig."
      end
    end

    # A fresh check: last time's "Ready to shoot" must not unlock this one.
    def start_camera_check
      RigCheck.stop_for!(Current.user)
      RigCheck::Locate.clear!(Current.user)
      RigCheck::Locate.start!(user: Current.user, camera: Current.user.last_camera, target:)
    end

    # A new camera brings its own microphone (Kiyo with Kiyo, iPhone with iPhone).
    def pair_mic(camera)
      return if camera == Current.user.last_camera

      mic = CameraProbe.latest&.pairs&.dig(camera)
      Current.user.update!(last_mic: mic) if mic.present?
    end
end
