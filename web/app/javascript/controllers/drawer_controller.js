import { Controller } from "@hotwired/stimulus"

// The app's menu: a drawer that slides out from the left over the content, so
// no bar takes screen space. Opens from the ☰ button; closes on the ✕, a click
// outside it, Escape, or by following a link (Turbo swaps the page).
export default class extends Controller {
  static targets = [ "panel", "backdrop", "button" ]

  open() {
    this.panelTarget.classList.remove("-translate-x-full", "invisible")
    this.backdropTarget.classList.remove("opacity-0", "pointer-events-none")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.querySelector("a, button")?.focus()
  }

  close() {
    if (this.panelTarget.classList.contains("invisible")) return
    this.panelTarget.classList.add("-translate-x-full", "invisible")
    this.backdropTarget.classList.add("opacity-0", "pointer-events-none")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.focus()
  }
}
