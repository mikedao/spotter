import { Controller } from "@hotwired/stimulus"

// One announcement, appended to the range screen by a Turbo broadcast
// (Announcement): hands itself to the announcer and goes away.
export default class extends Controller {
  static values = { payload: Object }

  connect() {
    window.dispatchEvent(new CustomEvent("announcer:say", { detail: this.payloadValue }))
    this.element.remove()
  }
}
