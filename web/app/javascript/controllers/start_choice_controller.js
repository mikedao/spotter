import { Controller } from "@hotwired/stimulus"

// The wizard's Start step: picking what you are shooting fills in its shots per
// card and its groups (each option carries them: data-per-card, data-group-of).
// The plan block's own values come pre-filled; picking practice or a course swaps
// in theirs. Either field can still be changed by hand afterwards.
export default class extends Controller {
  static targets = [ "perCard" ]

  pick(event) {
    const option = event.target
    if (option.dataset.perCard) this.perCardTarget.value = option.dataset.perCard
    const group = this.element.querySelector(`input[name="practice_session[group_of]"][value="${option.dataset.groupOf || 0}"]`)
    if (group) group.checked = true
  }
}
