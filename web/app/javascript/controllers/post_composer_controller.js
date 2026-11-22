import { Controller } from "@hotwired/stimulus"

// The plan day's post composer (plan_day_shares/show): every option that changes
// the pictures - colors, name and gear, the day card's headline, its note and
// progress switches - carries data-preview-param="name"; changing one asks the
// server for each preview picture again with all of them (typing waits a moment),
// without reloading the page, so the caption typed so far stays. At most `max`
// pictures can be ticked: the rest are disabled until one is unticked.
export default class extends Controller {
  static targets = [ "image", "pick", "count" ]
  static values = { max: Number }

  connect() { this.limit() }

  refresh() {
    clearTimeout(this.pending)
    const params = this.params()
    for (const img of this.imageTargets) {
      const url = new URL(img.src, window.location.href)
      for (const [ key, value ] of Object.entries(params)) url.searchParams.set(key, value)
      img.src = url.toString()
    }
  }

  // Typing in the headline: redraw once the typing pauses.
  type() {
    clearTimeout(this.pending)
    this.pending = setTimeout(() => this.refresh(), 400)
  }

  limit() {
    const picked = this.pickTargets.filter((box) => box.checked).length
    for (const box of this.pickTargets) box.disabled = !box.checked && picked >= this.maxValue
    if (this.hasCountTarget) this.countTarget.textContent = `${picked} of ${this.maxValue} picked`
  }

  params() {
    const out = {}
    for (const field of this.element.querySelectorAll("[data-preview-param]")) {
      const name = field.dataset.previewParam
      if (field.type === "radio") { if (field.checked) out[name] = field.value }
      else if (field.type === "checkbox") out[name] = field.checked ? "1" : "0"
      else out[name] = field.value
    }
    return out
  }
}
