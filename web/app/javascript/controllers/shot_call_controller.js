import { Controller } from "@hotwired/stimulus"

// The call form on a shot's review page. Listens for taps on the close-ups
// (closeup:picked), fills the position fields, and previews the score that
// position gets under the pellet rule, pre-selecting its ring. The shooter can
// still pick a different ring: what they say is what is stored.
export default class extends Controller {
  static values = { tenDia: Number, stepDia: Number, innerTenDia: Number, markMm: Number }
  static targets = [ "x", "y", "preview", "ring" ]

  picked({ detail: { x, y } }) {
    this.xTarget.value = x
    this.yTarget.value = y
    const s = this.score(Math.hypot(x, y))
    this.previewTarget.textContent = `That position scores ${s.decimal.toFixed(1)} (ring ${s.ring})${s.innerTen ? ", inner ten" : ""}.`
    const radio = this.ringTargets.find(r => Number(r.value) === s.ring)
    if (radio) radio.checked = true
  }

  // TargetSpec#score: edge nearest the centre, piecewise decimals, truncated.
  score(r) {
    const rEdge = Math.max(r - this.markMmValue / 2, 0)
    const tenR = this.tenDiaValue / 2
    const step = this.stepDiaValue / 2
    let decimal, ring
    if (rEdge <= tenR) {
      decimal = 10 + 0.9 * (tenR - rEdge) / tenR
      ring = 10
    } else {
      const steps = (rEdge - tenR) / step
      decimal = 10 - steps
      ring = Math.max(0, 10 - Math.ceil(steps))
    }
    decimal = Math.floor(Math.min(Math.max(decimal, 0), 10.9) * 10 + 1e-9) / 10
    return { decimal, ring, innerTen: rEdge <= this.innerTenDiaValue / 2 }
  }
}
