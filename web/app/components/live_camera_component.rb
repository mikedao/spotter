# The live camera picture on the range screen, rings from the current baseline
# drawn on by the engine (which holds the camera and serves it; the web app
# relays it through PracticeSessionsController#camera). Refreshes itself a few
# times a second (live_camera_controller.js) and is never replaced by
# LiveBroadcast. Only while the session runs: afterwards there is no camera.
class LiveCameraComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def render? = @session.live?

  def call
    # No heading and a thin frame like the target's: the picture says what it is,
    # and it must fit on a laptop screen under the match clock and latest shot.
    render(CardComponent.new(padding: :none, class: "p-2", "aria-label": "Camera")) do
      tag.div(class: "relative aspect-video overflow-hidden rounded-md bg-gray-900",
              data: { controller: "live-camera", live_camera_url_value: camera_practice_session_path(@session) }) do
        safe_join([
          tag.img(alt: "Live camera view of the target", class: "size-full object-contain transition-opacity",
                  hidden: true, data: { live_camera_target: "image" }),   # until the first frame: no broken-image icon
          tag.p("Waiting for the camera…", class: "absolute inset-0 grid place-items-center text-sm text-gray-300",
                data: { live_camera_target: "status" })
        ])
      end
    end
  end
end
