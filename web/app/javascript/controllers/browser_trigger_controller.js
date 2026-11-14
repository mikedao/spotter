import { Controller } from "@hotwired/stimulus"
import ShotListener from "lib/shot_listener"

// The range screen as the shot trigger (BrowserTriggerComponent): listens on
// this device's microphone and sends every sharp sound near or over the trigger
// level to the engine, which applies its own rule (too quiet, too short, echo,
// paused) and logs the near misses - one rule, in one place. The button shows
// the state; pressing it after a refusal asks again.
export default class extends Controller {
  static values = { url: String, db: Number, ms: Number, nearDb: Number, https: String }

  connect() {
    this.listener = new ShotListener({
      onSound: (s) => this.sound(s),
      onState: (state, detail) => this.show(state, detail)
    })
    this.listener.start()
  }

  disconnect() {
    this.listener?.stop()
    clearTimeout(this.flash)
  }

  retry() {
    if (this.state === "insecure" && this.httpsValue) { window.location = this.httpsValue; return }
    if ([ "denied", "failed", "unsupported" ].includes(this.state)) { this.listener.stop(); this.listener.start() }
  }

  async sound({ over_db, len_ms, ago_ms }) {
    if (over_db < this.dbValue - this.nearDbValue) return
    const shot = over_db >= this.dbValue && len_ms >= this.msValue
    if (shot) this.heard(over_db)
    try {
      await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content },
        body: JSON.stringify({ ago_ms: Math.round(ago_ms), over_db: +over_db.toFixed(1), len_ms: Math.round(len_ms) })
      })
    } catch (error) { console.warn("trigger:", error) }
  }

  heard(db) {
    this.element.textContent = `🎤 Shot heard +${Math.round(db)} dB`
    clearTimeout(this.flash)
    this.flash = setTimeout(() => this.show(this.state), 2500)
  }

  show(state, detail) {
    this.state = state
    const [ label, title ] = {
      starting: [ "🎤 Starting…", "Asking for the microphone" ],
      listening: [ "🎤 Listening", `This device hears your shots (a shot: +${this.dbValue} dB over the room, ${this.msValue} ms)` ],
      "needs-tap": [ "🎤 Tap anywhere to listen", "The browser needs one tap or key press first" ],
      denied: [ "🎤 Mic blocked - allow it", "Allow the microphone for this site in the browser, then press here" ],
      insecure: [ "🎤 Needs https", this.httpsValue ? `Press to open ${this.httpsValue}` : "Open this page over https (bin/rails spotter:tls)" ],
      unsupported: [ "🎤 Not in this browser", "This browser can't listen here; the camera still finds each shot" ],
      failed: [ "🎤 Mic failed - retry", detail || "The microphone stopped" ]
    }[state] || [ "🎤", "" ]
    this.element.textContent = label
    this.element.title = title
    this.element.setAttribute("aria-pressed", String(state === "listening"))
    this.element.dataset.state = state
  }
}
