import { Controller } from "@hotwired/stimulus"

// The share page (shares/new): a colorway pill or the name-and-gear box redraws
// the preview pictures - each <img> asks the server for that picture again in
// the new colors - without reloading the page, so a caption typed so far stays.
// The hidden `identity` field carries the box to the form (an unticked checkbox
// sends nothing).
export default class extends Controller {
  static targets = ["image", "identity", "identityValue"]

  refresh() {
    const colors = this.element.querySelector("input[name=colors]:checked")?.value
    const identity = this.identityTarget.checked ? "1" : "0"
    this.identityValueTarget.value = identity
    for (const img of this.imageTargets) {
      const url = new URL(img.src, window.location.href)
      url.searchParams.set("colors", colors)
      url.searchParams.set("identity", identity)
      img.src = url.toString()
    }
  }
}
