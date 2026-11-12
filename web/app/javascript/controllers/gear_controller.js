import { Controller } from "@hotwired/stimulus"

// The session form's Gun / Pellets pickers (GearFieldsComponent): changing the
// gun picks the pellets last used with it, "New pellets…" opens the fields to
// type them in, and "New lot of these" copies the chosen pellets into those
// fields so only the lot needs typing.
export default class extends Controller {
  static targets = ["gun", "pellet", "newPellet", "newLotLink", "name", "head", "weight", "lot"]
  static values = { pelletByGun: Object }

  gunChanged() {
    const pellet = this.pelletByGunValue[this.gunTarget.value]
    if (pellet) {
      this.pelletTarget.value = String(pellet)
      this.pelletChanged()
    }
  }

  pelletChanged() {
    const value = this.pelletTarget.value
    this.newPelletTarget.hidden = value !== "new"
    this.newLotLinkTarget.hidden = value === "" || value === "new"
  }

  newLot() {
    const chosen = this.pelletTarget.selectedOptions[0]
    if (!chosen) return
    this.nameTarget.value = chosen.dataset.name || ""
    this.headTarget.value = chosen.dataset.head || ""
    this.weightTarget.value = chosen.dataset.weight || ""
    this.lotTarget.value = ""
    this.pelletTarget.value = "new"
    this.pelletChanged()
    this.lotTarget.focus()
  }
}
