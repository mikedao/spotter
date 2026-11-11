import { Controller } from "@hotwired/stimulus"

// Say where the pellet went through on a straightened close-up, by dragging the
// amber circle (as fl-shooters' correction screen does). Grab the circle and it
// follows the pointer, keeping the offset it was grabbed at, so it never jumps
// under the finger; press anywhere else and it jumps there, then follows while
// held. Arrow keys nudge it 0.1 mm (Shift: 1 mm).
//
// The close-up is top-down at a fixed px/mm centred on (cx, cy) mm, so a
// position maps straight to target millimetres (y up). Every move fills the call
// form's x/y fields and previews what that position scores under the pellet
// rule (closeup:picked -> shot_call_controller.js, which uses the same
// arithmetic as TargetSpec#score in Ruby and scoring.py in the engine).
const GRAB_SLOP_PX = 14   // screen px outside the circle that still grabs it (a fingertip)
const NUDGE_MM = 0.1

export default class extends Controller {
  static values = { cx: Number, cy: Number, ppm: Number, size: Number }
  static targets = [ "mark" ]

  connect() {
    this.drag = null
  }

  down(event) {
    if (event.button > 0) return
    event.preventDefault()
    this.element.focus({ preventScroll: true })
    this.element.setPointerCapture(event.pointerId)
    const p = this.toPx(event)
    const m = this.markPx()
    const grabbed = m && this.near(p, m)
    this.drag = { id: event.pointerId, du: grabbed ? m.u - p.u : 0, dv: grabbed ? m.v - p.v : 0 }
    this.element.style.cursor = "grabbing"
    this.place(p.u + this.drag.du, p.v + this.drag.dv)
  }

  move(event) {
    const p = this.toPx(event)
    if (!this.drag) {
      const m = this.markPx()
      this.element.style.cursor = m && this.near(p, m) ? "grab" : ""
      return
    }
    if (event.pointerId !== this.drag.id) return
    this.place(p.u + this.drag.du, p.v + this.drag.dv)
  }

  up(event) {
    if (!this.drag || event.pointerId !== this.drag.id) return
    this.drag = null
    this.element.style.cursor = ""
    if (this.element.hasPointerCapture?.(event.pointerId)) this.element.releasePointerCapture(event.pointerId)
  }

  key(event) {
    const steps = { ArrowLeft: [ -1, 0 ], ArrowRight: [ 1, 0 ], ArrowUp: [ 0, -1 ], ArrowDown: [ 0, 1 ] }[event.key]
    if (!steps) return
    event.preventDefault()
    const px = (event.shiftKey ? 10 : 1) * NUDGE_MM * this.ppmValue
    const m = this.markPx() || { u: this.sizeValue / 2, v: this.sizeValue / 2 }
    this.place(m.u + steps[0] * px, m.v + steps[1] * px)
  }

  // --- helpers ---------------------------------------------------------------

  place(u, v) {
    u = Math.min(Math.max(u, 0), this.sizeValue)
    v = Math.min(Math.max(v, 0), this.sizeValue)
    if (this.hasMarkTarget) {
      this.markTarget.setAttribute("cx", u.toFixed(1))
      this.markTarget.setAttribute("cy", v.toFixed(1))
    }
    const x = this.cxValue + (u - this.sizeValue / 2) / this.ppmValue
    const y = this.cyValue - (v - this.sizeValue / 2) / this.ppmValue
    this.dispatch("picked", { detail: { x: Number(x.toFixed(2)), y: Number(y.toFixed(2)) }, prefix: "closeup" })
  }

  // pointer -> close-up pixels
  toPx(event) {
    const box = this.element.getBoundingClientRect()
    return { u: (event.clientX - box.left) / box.width * this.sizeValue,
             v: (event.clientY - box.top) / box.height * this.sizeValue }
  }

  // Where the amber circle is now, or null before the first position is given.
  markPx() {
    if (!this.hasMarkTarget) return null
    const u = Number(this.markTarget.getAttribute("cx"))
    const v = Number(this.markTarget.getAttribute("cy"))
    return u < 0 || v < 0 ? null : { u, v }
  }

  near(p, m) {
    const scale = this.sizeValue / this.element.getBoundingClientRect().width   // close-up px per screen px
    const r = Number(this.markTarget.getAttribute("r")) + GRAB_SLOP_PX * scale
    return Math.hypot(p.u - m.u, p.v - m.v) <= r
  }
}
