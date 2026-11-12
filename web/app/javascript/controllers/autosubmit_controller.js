import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as a field changes: the journal's filters apply
// without an Apply button.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
