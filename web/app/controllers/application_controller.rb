class ApplicationController < ActionController::Base
  # A toast without leaving the page (the live range screen: leaving it stops its
  # microphone and announcer). The panels are redrawn by the live broadcast.
  def render_toast(kind, message)
    render turbo_stream: turbo_stream.append_all("body", FlashComponent.new(flash: { kind.to_s => message }))
  end

  include Authentication

  helper_method :current_user
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    # Set by Authentication (Current.session); the user follows from it.
    def current_user = Current.user
end
