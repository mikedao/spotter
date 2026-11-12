import { Controller } from "@hotwired/stimulus"

// "Save as PDF": the browser's print dialog, where "Save as PDF" is a destination.
export default class extends Controller {
  print() {
    window.print()
  }
}
