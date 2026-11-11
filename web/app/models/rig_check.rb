# Rig setup checks (the camera check and the sound check). They use the same
# camera and microphone as a practice session, so none runs during a session, and
# only one sound check runs at a time.
module RigCheck
  class Busy < StandardError; end

  def self.ensure_free!
    if (running = EngineRunner.running)
      raise Busy, "#{running.user.name} is shooting - the camera and microphone are in use"
    end
    raise Busy, "a sound check is running" if RigCheck::Listen.running?
  end
end
