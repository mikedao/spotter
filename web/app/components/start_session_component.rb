# Start a practice session: pick the target and how many shots go on a card, and
# the web app launches the engine (EngineRunner). While anyone's session runs it
# says who is shooting instead - one camera, one session at a time.
class StartSessionComponent < ApplicationComponent
  def initialize(running:, user:) = (@running, @user = running, user)
end
