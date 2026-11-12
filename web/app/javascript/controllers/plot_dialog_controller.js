import { Controller } from "@hotwired/stimulus"

// The live range screen's plot panel: a "plot it" link loads a capture into the
// dialog's turbo-frame (ShotsController#plot) and the dialog opens over the range
// screen - the page, its sound and camera carry on. Once scored, the frame shows
// the result (data-plot-done) and the dialog closes itself.
export default class extends Controller {
  static targets = [ "frame" ]

  connect() {
    this.loaded = () => {
      if (this.frameTarget.querySelector("[data-plot-done]")) {
        setTimeout(() => this.close(), 1500)
      } else if (!this.element.open) {
        this.element.showModal()
      }
    }
    this.frameTarget.addEventListener("turbo:frame-load", this.loaded)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:frame-load", this.loaded)
  }

  close() {
    if (this.element.open) this.element.close()
    this.frameTarget.innerHTML = ""
    this.frameTarget.removeAttribute("src")
  }
}
