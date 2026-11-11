import { Controller } from "@hotwired/stimulus"

// Tap a straightened close-up to say where the pellet went through. The close-up
// is top-down at a fixed px/mm centred on (cx, cy) mm, so a tap maps straight to
// target millimetres (y up). Fills the call form's x/y fields, moves the amber
// mark, and shows what that position scores under the pellet rule - the same
// arithmetic as TargetSpec#score in Ruby and scoring.py in the engine.
export default class extends Controller {
  static values = { cx: Number, cy: Number, ppm: Number, size: Number }
  static targets = [ "mark" ]

  tap(event) {
    const box = this.element.getBoundingClientRect()
    const u = (event.clientX - box.left) / box.width * this.sizeValue
    const v = (event.clientY - box.top) / box.height * this.sizeValue
    const x = this.cxValue + (u - this.sizeValue / 2) / this.ppmValue
    const y = this.cyValue - (v - this.sizeValue / 2) / this.ppmValue

    if (this.hasMarkTarget) {
      this.markTarget.setAttribute("cx", u.toFixed(1))
      this.markTarget.setAttribute("cy", v.toFixed(1))
    }
    this.dispatch("picked", { detail: { x: Number(x.toFixed(2)), y: Number(y.toFixed(2)) }, prefix: "closeup" })
  }
}
