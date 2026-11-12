import { Controller } from "@hotwired/stimulus"

// Scoring a capture by hand: a tap on the after picture marks the hole and
// sends its pixel in the FULL-SIZE picture (what the engine locates the target
// in), whatever size the picture is shown at.
export default class extends Controller {
  static targets = [ "image", "mark", "px", "py", "submit" ]

  pick(event) {
    const image = this.imageTarget
    const box = image.getBoundingClientRect()
    const x = event.clientX - box.left
    const y = event.clientY - box.top
    if (x < 0 || y < 0 || x > box.width || y > box.height) return

    this.pxTarget.value = (x * image.naturalWidth / box.width).toFixed(2)
    this.pyTarget.value = (y * image.naturalHeight / box.height).toFixed(2)
    this.markTarget.style.left = `${x}px`
    this.markTarget.style.top = `${y}px`
    this.markTarget.hidden = false
    this.submitTarget.disabled = false
  }
}
