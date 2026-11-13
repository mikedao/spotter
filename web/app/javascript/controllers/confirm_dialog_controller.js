import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The app's confirmation modal (ConfirmDialogComponent) in place of the browser's
// confirm() box: while it is on the page it is Turbo's confirm method, so every
// data-turbo-confirm asks here. Resolves true on the confirm button, false on
// Cancel, Esc or a click outside.
export default class extends Controller {
  static targets = [ "message", "cancel", "danger", "proceed" ]

  connect() {
    this.method = (message, form, submitter) => this.ask(message, form, submitter)
    Turbo.config.forms.confirm = this.method
  }

  disconnect() {
    this.finish(false)
    if (Turbo.config.forms.confirm === this.method) Turbo.config.forms.confirm = undefined
  }

  ask(message, form, submitter) {
    this.finish(false)   // never two questions at once
    const destructive = (form?.querySelector("input[name=_method]")?.value || form?.method || "").toLowerCase() === "delete"
    const label = submitter?.dataset.confirmButton || form?.dataset.confirmButton
    const button = destructive ? this.dangerTarget : this.proceedTarget
    this.dangerTarget.hidden = !destructive
    this.proceedTarget.hidden = destructive
    button.textContent = label || (destructive ? "Delete" : "Continue")
    this.messageTarget.textContent = message
    this.element.showModal()
    ;(destructive ? this.cancelTarget : button).focus()   // a delete needs a deliberate click
    return new Promise(resolve => { this.resolve = resolve })
  }

  accept() { this.finish(true) }
  cancel() { this.finish(false) }

  // A click on the dialog element itself is a click on the backdrop around the panel.
  backdrop(event) { if (event.target === this.element) this.finish(false) }

  finish(answer) {
    const resolve = this.resolve
    this.resolve = null
    if (this.element.open) this.element.close()
    resolve?.(answer)
  }
}
