import { Controller } from "@hotwired/stimulus"

// On the Start form: choosing a camera selects that camera's own microphone
// (its radio carries data-mic, worked out by CameraProbe.pair), when the menu
// has it. Cameras without a matching mic leave the microphone as it is.
export default class extends Controller {
  static targets = [ "mic" ]

  cameraChanged(event) {
    const input = event.target
    if (input.name !== "practice_session[camera]" || !input.dataset.mic || !this.hasMicTarget) return
    if ([ ...this.micTarget.options ].some(o => o.value === input.dataset.mic)) {
      this.micTarget.value = input.dataset.mic
    }
  }
}
