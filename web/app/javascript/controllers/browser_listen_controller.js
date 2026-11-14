import { Controller } from "@hotwired/stimulus"
import ShotListener from "lib/shot_listener"

// The wizard's sound check on THIS browser's microphone (BrowserListenComponent):
// meter, the sounds heard (newest first, the last few), each marked as the engine
// would judge it, and Next once one would trigger - reported to the server so
// Start says "heard a shot" and the next session can skip the check.
const LATEST = 5

export default class extends Controller {
  static targets = [ "phase", "dot", "bar", "level", "summary", "next", "locked", "table", "sounds", "insecure" ]
  static values = { db: Number, ms: Number, scale: Number, heardUrl: String }

  connect() {
    this.heard = []
    this.started = performance.now()
    this.listener = new ShotListener({
      onSound: (s) => this.sound(s),
      onLevel: (l) => this.level(l),
      onState: (state, detail) => this.state(state, detail)
    })
    this.listener.start()
  }

  disconnect() { this.listener?.stop() }

  state(state, detail) {
    const text = {
      starting: "Starting the microphone… (allow it when the browser asks)",
      listening: "Measuring the room - stay quiet",
      "needs-tap": "Tap anywhere on the page to start listening",
      denied: "The microphone was blocked: allow it for this site in the browser, then Listen again",
      insecure: "This page can't use the microphone over http",
      unsupported: "This browser can't listen here - use camera only",
      failed: `The microphone failed${detail ? `: ${detail}` : ""}`
    }[state]
    if (text) this.phaseTarget.textContent = text
    this.listening = state === "listening"
    this.dotTarget.className = `inline-block size-2.5 rounded-full ${this.listening ? "animate-pulse bg-green-600" : "bg-gray-400"}`
    if (this.hasInsecureTarget) this.insecureTarget.hidden = state !== "insecure"
  }

  level({ over_db, floor_dbfs }) {
    if (floor_dbfs === null) return
    if (this.listening) this.phaseTarget.textContent = "Listening - fire when ready"
    const over = Math.max(0, over_db)
    this.barTarget.style.width = `${Math.round(Math.min(over, this.scaleValue) / this.scaleValue * 100)}%`
    this.barTarget.className = `h-full ${over >= this.dbValue ? "bg-green-600" : "bg-blue-600"}`
    this.levelTarget.textContent = `Now +${Math.round(over)} dB over the room (floor ${floor_dbfs.toFixed(1)} dBFS).`
  }

  sound({ over_db, len_ms }) {
    const trigger = over_db >= this.dbValue && len_ms >= this.msValue
    this.heard.push({ n: this.heard.length + 1, t: (performance.now() - this.started) / 1000, over_db, len_ms, trigger })
    this.render()
    if (trigger) this.passed(over_db, len_ms)
  }

  async passed(over_db, len_ms) {
    this.nextTarget.hidden = false
    this.lockedTarget.hidden = true
    if (this.reported) return
    this.reported = true
    try {
      await fetch(this.heardUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content },
        body: JSON.stringify({ over_db: +over_db.toFixed(1), len_ms: Math.round(len_ms) })
      })
    } catch (error) { this.reported = false; console.warn("sound check:", error) }
  }

  render() {
    const shots = this.heard.filter((s) => s.trigger).length
    this.summaryTarget.hidden = false
    this.summaryTarget.innerHTML = `<strong>${shots} ${shots === 1 ? "sound" : "sounds"} would trigger</strong> out of ${this.heard.length} heard so far.` +
      (shots === 0 && this.heard.length >= 3 ? " If those were shots, this device is too far from the gun or its microphone is muffled." : "")
    this.tableTarget.hidden = false
    this.soundsTarget.replaceChildren(...this.heard.slice(-LATEST).reverse().map((s) => this.row(s)))
  }

  row(s) {
    const tr = document.createElement("tr")
    const cells = [ s.n, `${s.t.toFixed(1)} s`, `+${Math.round(s.over_db)} dB`, `${Math.round(s.len_ms)} ms` ]
    cells.forEach((text, i) => {
      const td = document.createElement("td")
      td.textContent = text
      if (i === 0) td.className = "py-1.5"
      tr.append(td)
    })
    const verdict = document.createElement("td")
    const span = document.createElement("span")
    if (s.trigger) {
      span.textContent = "would trigger"
      span.className = "rounded bg-green-100 px-2 py-0.5 text-green-900 dark:bg-green-950 dark:text-green-200"
    } else {
      span.textContent = s.over_db < this.dbValue ? "too quiet" : "too short"
      span.className = "text-gray-600 dark:text-gray-300"
    }
    verdict.append(span)
    tr.append(verdict)
    return tr
  }
}
