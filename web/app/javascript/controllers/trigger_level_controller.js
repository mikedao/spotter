import { Controller } from "@hotwired/stimulus"

// The sound check's trigger level (TriggerLevelComponent): saved as it changes,
// then announced to the page ("trigger-level:changed") so the browser's sound
// check re-judges what it has heard at the new level.
export default class extends Controller {
  static targets = [ "input", "status" ]
  static values = { url: String }

  async save() {
    this.statusTarget.textContent = "Saving…"
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json",
                   "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content },
        body: JSON.stringify({ db: Number(this.inputTarget.value) })
      })
      if (!response.ok) throw new Error(response.statusText)
      const { db } = await response.json()
      this.inputTarget.value = Math.round(db)
      this.statusTarget.textContent = "Saved"
      window.dispatchEvent(new CustomEvent("trigger-level:changed", { detail: { db } }))
    } catch (error) {
      this.statusTarget.textContent = `Not saved: ${error.message}`
    }
  }
}
