import { Controller } from "@hotwired/stimulus"

// The range officer's clock on the range screen: counts down to the engine's
// ends_at (ISO time) a few times a second, turning amber at `warn` seconds left
// and red at `alarm`. The panel around it is replaced on each engine event, which
// brings a new ends_at; this only ticks between them.
export default class extends Controller {
  static values = { endsAt: String, warn: Number, alarm: Number }

  connect() {
    this.ends = Date.parse(this.endsAtValue)
    this.tick()
    this.timer = setInterval(() => this.tick(), 250)
  }

  disconnect() { clearInterval(this.timer) }

  tick() {
    const left = Math.max(0, Math.ceil((this.ends - Date.now()) / 1000))
    const h = Math.floor(left / 3600), m = Math.floor((left % 3600) / 60), s = left % 60
    const pad = n => String(n).padStart(2, "0")
    this.element.textContent = h ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
    this.element.classList.toggle("text-amber-600", left <= this.warnValue && left > this.alarmValue)
    this.element.classList.toggle("text-red-600", left <= this.alarmValue)
  }
}
