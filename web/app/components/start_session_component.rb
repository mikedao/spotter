# The Practice page's way into a new session: a New session button that looks
# for cameras and microphones and opens the setup wizard (SessionSetupController).
# While anyone's session runs it says who is shooting instead - one camera, one
# session at a time.
class StartSessionComponent < ApplicationComponent
  def initialize(running:, user:) = (@running, @user = running, user)
end
