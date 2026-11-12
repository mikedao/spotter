import { Controller } from "@hotwired/stimulus"

// Plays an announcer voice's sample on Rig setup, one at a time: press ▶ to
// play, press it again (or another voice) to stop. A voice whose sample hasn't
// been made yet takes ~20 s the first time; the status line says so.
export default class extends Controller {
  static targets = [ "status" ]

  disconnect() { this.stop() }

  async toggle({ params: { url }, currentTarget: button }) {
    const same = this.button === button
    this.stop()
    if (same) return

    this.button = button
    button.textContent = "…"
    this.say("Getting the sample… (the first time for a voice takes about 20 seconds)")
    const token = (this.token = {})
    try {
      const response = await fetch(url)
      if (token !== this.token) return            // another voice was pressed meanwhile
      if (!response.ok) throw new Error(await response.text() || "the sample couldn't be made")
      this.objectUrl = URL.createObjectURL(await response.blob())
      this.audio = new Audio(this.objectUrl)
      this.audio.addEventListener("ended", () => this.stop())
      await this.audio.play()
      button.textContent = "■"
      button.setAttribute("aria-label", button.getAttribute("aria-label").replace("Play", "Stop"))
      this.say("")
    } catch (error) {
      if (token === this.token) { this.stop(); this.say(`Couldn't play it: ${error.message}`) }
    }
  }

  stop() {
    this.token = null
    if (this.audio) { this.audio.pause(); this.audio = null }
    if (this.objectUrl) { URL.revokeObjectURL(this.objectUrl); this.objectUrl = null }
    if (this.button) {
      this.button.textContent = "▶"
      this.button.setAttribute("aria-label", this.button.getAttribute("aria-label").replace("Stop", "Play"))
      this.button = null
    }
  }

  say(text) { if (this.hasStatusTarget) this.statusTarget.textContent = text }
}
