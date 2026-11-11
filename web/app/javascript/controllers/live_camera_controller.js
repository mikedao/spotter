import { Controller } from "@hotwired/stimulus"

// The range screen's live camera picture: fetches the latest frame from the
// engine (relayed by the web app) a few times a second, the next only after the
// last has arrived, so a slow link never piles up requests. Pauses while the
// tab is hidden. 204 or an error = no picture right now: keep the last one,
// dimmed, say so, and try again every couple of seconds. 410 = the session
// ended: remove the picture.
export default class extends Controller {
  static targets = [ "image", "status" ]
  static values = { url: String, every: { type: Number, default: 300 } }

  connect() {
    this.running = true
    this.tick()
  }

  disconnect() {
    this.running = false
    clearTimeout(this.timer)
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  }

  async tick() {
    if (!this.running) return
    let wait = this.everyValue
    if (!document.hidden) {
      try {
        const response = await fetch(this.urlValue, { cache: "no-store" })
        if (response.status === 200) {
          const url = URL.createObjectURL(await response.blob())
          this.imageTarget.src = url
          if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
          this.objectUrl = url
          this.live(true)
        } else if (response.status === 410) {
          this.element.closest("section")?.remove()   // session over: no camera any more
          return
        } else {
          this.live(false)
          wait = 2000
        }
      } catch {
        this.live(false)
        wait = 2000
      }
    }
    if (this.running) this.timer = setTimeout(() => this.tick(), wait)
  }

  live(on) {
    this.imageTarget.classList.toggle("opacity-40", !on)
    this.statusTarget.hidden = on
    if (!on && this.objectUrl) this.statusTarget.textContent = "No picture from the camera right now"
  }
}
