# The live camera picture on the range screen, rings from the current baseline
# drawn on by the engine (which holds the camera and serves it; the web app
# relays it through PracticeSessionsController#camera). Refreshes itself a few
# times a second (live_camera_controller.js) and is never replaced by
# LiveBroadcast. Only while the session runs: afterwards there is no camera.
class LiveCameraComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def render? = @session.live?

  def call
    render(CardComponent.new(title: "Camera")) do
      tag.div(class: "relative aspect-video overflow-hidden rounded-md bg-gray-900",
              data: { controller: "live-camera", live_camera_url_value: camera_practice_session_path(@session) }) do
        safe_join([
          tag.img(alt: "Live camera view of the target", class: "size-full object-contain transition-opacity",
                  data: { live_camera_target: "image" }),
          tag.p("Waiting for the camera…", class: "absolute inset-0 grid place-items-center text-sm text-gray-300",
                data: { live_camera_target: "status" })
        ])
      end
    end
  end
end
