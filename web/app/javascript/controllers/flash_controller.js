import { Controller } from "@hotwired/stimulus"

// One toast (FlashComponent): fades away after `dismissAfter` ms (0 = stays
// until closed), held while the pointer is on it.
export default class extends Controller {
  static values = { dismissAfter: Number }

  connect() {
    this.resume()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  pause() {
    clearTimeout(this.timer)
  }

  resume() {
    if (this.dismissAfterValue > 0) this.timer = setTimeout(() => this.close(), this.dismissAfterValue)
  }

  close() {
    clearTimeout(this.timer)
    this.element.classList.add("opacity-0", "-translate-y-2")
    setTimeout(() => this.element.remove(), 300)
  }
}
