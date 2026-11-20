import { Controller } from "@hotwired/stimulus"

// Swapping days on the plan page. Drag a day onto another (mouse), or tap "Swap" on
// one and then on the other (touch, where a drag would scroll the page). Either way
// the pair goes to the server in the hidden form; it answers with the new calendar.
export default class extends Controller {
  static targets = ["day", "form", "from", "to", "open", "hint"]

  connect() { this.picked = null }

  dragStart(event) {
    this.dragging = event.currentTarget.dataset.ref
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragging)
    event.currentTarget.classList.add("opacity-50")
  }

  dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
    this.dayTargets.forEach(day => day.classList.remove("ring-2", "ring-blue-500"))
  }

  dragOver(event) {
    if (!this.dragging) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("ring-2", "ring-blue-500")
  }

  dragLeave(event) { event.currentTarget.classList.remove("ring-2", "ring-blue-500") }

  drop(event) {
    event.preventDefault()
    const from = this.dragging
    this.dragging = null
    this.submit(from, event.currentTarget.dataset.ref, event.currentTarget)
  }

  // The "Swap" button on a day: first tap picks it, second tap on another swaps; the same one again cancels.
  pick(event) {
    event.preventDefault()
    event.stopPropagation()
    const day = event.currentTarget.closest("[data-ref]")
    if (!this.picked) {
      this.picked = day.dataset.ref
      day.classList.add("ring-2", "ring-blue-500")
      if (this.hasHintTarget) this.hintTarget.hidden = false
    } else if (this.picked === day.dataset.ref) {
      this.clear()
    } else {
      this.submit(this.picked, day.dataset.ref, day)
    }
  }

  clear() {
    this.picked = null
    this.dayTargets.forEach(day => day.classList.remove("ring-2", "ring-blue-500"))
    if (this.hasHintTarget) this.hintTarget.hidden = true
  }

  submit(from, to, element) {
    if (!from || !to || from === to) return this.clear()
    this.fromTarget.value = from
    this.toTarget.value = to
    this.openTarget.value = element.closest("[data-week]")?.dataset.week || ""
    this.formTarget.requestSubmit()
  }
}
