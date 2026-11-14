import { Controller } from "@hotwired/stimulus"
import ShotListener from "lib/shot_listener"

// The wizard's sound check on THIS browser's microphone (BrowserListenComponent):
// meter, the sounds heard (newest first, the last few), each judged at this mic's
// trigger level, and Next once one would trigger - reported to the server so
// Start says "heard a shot" and the next session can skip the check. Moving the
// trigger level (TriggerLevelComponent) re-judges everything heard so far.
const LATEST = 5

export default class extends Controller {
  static targets = [ "phase", "dot", "bar", "level", "summary", "next", "locked", "table", "sounds", "insecure", "line", "levelText" ]
  static values = { db: Number, ms: Number, scale: Number, heardUrl: String }

  connect() {
    this.heard = []
    this.reportedAt = null   // the level a pass was last reported at
    this.started = performance.now()
    this.levelChanged = ({ detail }) => this.setLevel(detail.db)
    window.addEventListener("trigger-level:changed", this.levelChanged)
    this.listener = new ShotListener({
      onSound: (s) => this.sound(s),
      onLevel: (l) => this.level(l),
      onState: (state, detail) => this.state(state, detail)
    })
    this.listener.start()
  }

  disconnect() {
    window.removeEventListener("trigger-level:changed", this.levelChanged)
    this.listener?.stop()
  }

  triggers(s) { return s.over_db >= this.dbValue && s.len_ms >= this.msValue }

  setLevel(db) {
    this.dbValue = db
    this.lineTarget.style.left = `${Math.round(db / this.scaleValue * 100)}%`
    this.levelTextTarget.textContent = Math.round(db)
    this.render()
  }

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
    this.heard.push({ n: this.heard.length + 1, t: (performance.now() - this.started) / 1000, over_db, len_ms })
    this.render()
  }

  // Next unlocks while any sound heard would trigger at the current level; the
  // loudest is reported (once per level) so the pass is remembered at that level.
  async verdict() {
    const shots = this.heard.filter((s) => this.triggers(s))
    this.nextTarget.hidden = shots.length === 0
    this.lockedTarget.hidden = shots.length > 0
    if (shots.length === 0 || this.reportedAt === this.dbValue) return
    const loudest = shots.reduce((a, b) => (b.over_db > a.over_db ? b : a))
    this.reportedAt = this.dbValue
    try {
      await fetch(this.heardUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content },
        body: JSON.stringify({ over_db: +loudest.over_db.toFixed(1), len_ms: Math.round(loudest.len_ms) })
      })
    } catch (error) { this.reportedAt = null; console.warn("sound check:", error) }
  }

  render() {
    if (this.heard.length === 0) return this.verdict()
    const shots = this.heard.filter((s) => this.triggers(s)).length
    // sounds long enough to be a shot: their loudness range helps set the level
    const long = this.heard.filter((s) => s.len_ms >= this.msValue).map((s) => Math.round(s.over_db))
    this.summaryTarget.hidden = false
    this.summaryTarget.innerHTML = `<strong>${shots} ${shots === 1 ? "sound" : "sounds"} would trigger</strong> out of ${this.heard.length} heard so far.` +
      (long.length ? ` Sounds long enough to be a shot: +${Math.min(...long)} to +${Math.max(...long)} dB.` : "") +
      (shots === 0 && this.heard.length >= 3 ? " If those were shots, lower the trigger level, or move this device closer to the gun." : "")
    this.tableTarget.hidden = false
    this.soundsTarget.replaceChildren(...this.heard.slice(-LATEST).reverse().map((s) => this.row(s)))
    this.verdict()
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
    if (this.triggers(s)) {
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
