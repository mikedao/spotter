import { Controller } from "@hotwired/stimulus"

// The slow dry fire timer (Pardini). Per shot: a few seconds to raise and settle,
// then up to `limit` seconds to break the shot - tap Shot (or Space) as it breaks.
// A shot not broken in time, or let down (button or Escape), does not count and is
// taken again, so the run goes on until `shots` are fired. A short rest between shots,
// a longer one between strings (none after the last shot). Tones are made here, the
// cues (raise, hold, lower, rest, three, two, one, done) are the shooter's Kokoro
// voice, fetched first and played through WebAudio (browser voice for any missing).
// The clock runs on elapsed time with overshoot carried. At the end the page submits
// shots fired, let downs and the summed raise-to-break time to SlowDrillsController#create.
const VOICE_KEY = "slowDrillVoice"
const TICK_MS = 100
const CUE_LOAD_S = 4

export default class extends Controller {
  static targets = [ "progress", "phase", "count", "tally", "start", "shot", "letDown", "pause", "stop", "voice", "form", "shotsFired", "letDowns", "breakSeconds" ]
  static values = { shots: Number, string: Number, limit: Number, between: Number, stringRest: Number, settle: Number, indexUrl: String, cues: Object }

  connect() {
    this.running = false
    this.sources = []
    this.cueBuffers = new Map()
    this.voiceTarget.checked = this.stored() !== "off"
  }

  disconnect() { this.teardown() }

  async start() {
    if (this.starting) return
    this.starting = true
    this.startTarget.disabled = true
    this.ctx ||= new AudioContext()
    this.ctx.resume()
    this.keepAwake()
    if (this.voiceTarget.checked) await this.loadCues()
    this.shotsDone = 0
    this.letDowns = 0
    this.breakTime = 0
    this.inString = 0
    this.running = true
    this.paused = false
    this.startTarget.hidden = true
    this.pauseTarget.hidden = this.stopTarget.hidden = false
    this.starting = false
    this.enter({ kind: "settle", secs: this.settleValue }, 0)
    this.last = performance.now()
    this.timer = setInterval(() => this.tick(), TICK_MS)
  }

  pause() {
    if (!this.running) return
    this.paused = !this.paused
    this.pauseTarget.textContent = this.paused ? "Resume" : "Pause"
    this.phaseTarget.textContent = this.paused ? "Paused" : this.label(this.phase)
    this.last = performance.now()
  }

  // The shot broke: counts, with the time from the start of the hold window.
  count_() {
    this.shotsDone += 1
    this.inString += 1
    this.breakTime += Math.min(this.elapsed, this.limitValue)
  }

  fired() {
    if (!this.running || this.paused || this.phase.kind !== "hold") return
    this.count_()
    if (this.shotsDone >= this.shotsValue) return this.finish()
    if (this.inString >= this.stringValue) {
      this.inString = 0
      this.enter({ kind: "stringrest", secs: this.stringRestValue }, 0)
    } else {
      this.enter({ kind: "gap", secs: this.betweenValue }, 0)
    }
  }

  // Not broken in time, or let down: does not count, and is taken again after a pause.
  letDown() {
    if (!this.running || this.paused || this.phase.kind !== "hold") return
    this.letDowns += 1
    this.enter({ kind: "gap", secs: this.betweenValue }, 0)
  }

  stop() {
    if (this.running) this.finish()
  }

  key(event) {
    if (!this.running || event.target.closest("button, input, a, textarea, select")) return
    if (event.code === "Space") { event.preventDefault(); this.fired() }
    else if (event.key === "Escape") this.letDown()
  }

  rememberVoice() {
    try { localStorage.setItem(VOICE_KEY, this.voiceTarget.checked ? "on" : "off") } catch { /* private window */ }
    if (!this.voiceTarget.checked) window.speechSynthesis?.cancel()
  }

  tick() {
    const now = performance.now()
    const dt = (now - this.last) / 1000
    this.last = now
    if (this.paused) return
    this.elapsed += dt
    if (this.elapsed >= this.phase.secs) {
      const over = this.elapsed - this.phase.secs
      if (this.phase.kind === "settle") this.enter({ kind: "hold", secs: this.limitValue }, over)
      else if (this.phase.kind === "hold") this.letDown()   // out of time
      else this.enter({ kind: "settle", secs: this.settleValue }, over)
    }
    if (this.running) this.render()
  }

  enter(phase, carry) {
    this.phase = phase
    this.elapsed = carry
    this.shown = null
    this.shotTarget.hidden = this.letDownTarget.hidden = phase.kind !== "hold"
    this.cue(phase.kind)
    this.render()
  }

  finish() {
    this.teardown()
    this.running = false
    this.cue("done")
    this.pauseTarget.hidden = this.shotTarget.hidden = this.letDownTarget.hidden = this.stopTarget.hidden = true
    if (this.shotsDone + this.letDowns === 0) return window.Turbo.visit(this.indexUrlValue)
    this.phaseTarget.textContent = "Saving…"
    this.shotsFiredTarget.value = this.shotsDone
    this.letDownsTarget.value = this.letDowns
    this.breakSecondsTarget.value = this.breakTime.toFixed(1)
    setTimeout(() => this.formTarget.requestSubmit(), this.voiceTarget.checked ? 1200 : 300)
  }

  teardown() {
    clearInterval(this.timer)
    this.timer = null
    this.wake?.release()
    this.wake = null
    window.speechSynthesis?.cancel()
    this.sources.forEach((source) => { try { source.stop() } catch { /* already over */ } })
    this.sources = []
  }

  render() {
    const remaining = Math.max(0, Math.ceil(this.phase.secs - this.elapsed))
    this.countTarget.textContent = remaining
    this.countTarget.dataset.phase = this.phase.kind === "stringrest" ? "gap" : this.phase.kind
    const string = Math.floor(this.shotsDone / this.stringValue) + 1
    this.progressTarget.textContent = `Shot ${this.shotsDone + 1} of ${this.shotsValue} · string ${string}`
    this.tallyTarget.textContent = this.letDowns ? `${this.shotsDone} fired · ${this.letDowns} let down` : `${this.shotsDone} fired`
    if (!this.paused) this.phaseTarget.textContent = this.label(this.phase)
    const resting = this.phase.kind === "gap" || this.phase.kind === "stringrest"
    if (resting && remaining <= 3 && remaining > 0 && remaining !== this.shown) this.countdown(remaining)
    this.shown = remaining
  }

  label(phase) {
    return { settle: "Raise and settle", hold: "Break the shot. Tap Shot, or let down.", gap: "Gun down. Rest.", stringrest: "String done. Gun down, rest." }[phase.kind]
  }

  cue(kind) {
    const tones = { settle: [ [ 523 ], 0.15 ], hold: [ [ 880 ], 0.25 ], gap: [ [ 880, 660 ], 0.12 ], stringrest: [ [ 880, 660 ], 0.12 ], done: [ [ 523, 659, 784 ], 0.14 ] }[kind]
    const end = this.beep(...tones)
    this.speak({ settle: [ "raise" ], hold: [ "hold" ], gap: [ "lower" ], stringrest: [ "lower", "rest" ], done: [ "done" ] }[kind], end)
  }

  countdown(remaining) {
    const word = { 3: "three", 2: "two", 1: "one" }[remaining]
    if (this.voiceTarget.checked && this.cueBuffers.has(word)) this.speak([ word ], this.ctx.currentTime)
    else this.beep([ 660 ], 0.05)
  }

  speak(words, at) {
    if (!this.voiceTarget.checked) return
    this.sources.forEach((source) => { try { source.stop() } catch { /* already over */ } })
    this.sources = []
    window.speechSynthesis?.cancel()
    const buffers = words.map((word) => this.cueBuffers.get(word))
    if (buffers.every(Boolean) && this.ctx) {
      let start = Math.max(at, this.ctx.currentTime) + 0.05
      buffers.forEach((buffer) => {
        const source = this.ctx.createBufferSource()
        source.buffer = buffer
        source.connect(this.ctx.destination)
        source.start(start)
        this.sources.push(source)
        start += buffer.duration + 0.2
      })
    } else if (window.speechSynthesis) {
      window.speechSynthesis.speak(new SpeechSynthesisUtterance(words.join(", ")))
    }
  }

  async loadCues() {
    const loads = Object.entries(this.cuesValue).map(async ([ word, url ]) => {
      const response = await fetch(url)
      if (!response.ok) throw new Error(`${response.status} ${url}`)
      this.cueBuffers.set(word, await this.ctx.decodeAudioData(await response.arrayBuffer()))
    })
    const timeout = new Promise((resolve) => setTimeout(resolve, CUE_LOAD_S * 1000))
    await Promise.race([ Promise.allSettled(loads), timeout ])
  }

  beep(frequencies, length) {
    if (!this.ctx) return 0
    let at = this.ctx.currentTime + 0.02
    frequencies.forEach((frequency) => {
      const oscillator = this.ctx.createOscillator()
      const gain = this.ctx.createGain()
      oscillator.frequency.value = frequency
      gain.gain.setValueAtTime(0.0001, at)
      gain.gain.exponentialRampToValueAtTime(0.25, at + 0.01)
      gain.gain.exponentialRampToValueAtTime(0.0001, at + length)
      oscillator.connect(gain).connect(this.ctx.destination)
      oscillator.start(at)
      oscillator.stop(at + length + 0.02)
      at += length + 0.04
    })
    return at
  }

  async keepAwake() {
    if (this.wake || !navigator.wakeLock) return
    try {
      this.wake = await navigator.wakeLock.request("screen")
      this.wake.addEventListener("release", () => { this.wake = null })
    } catch { this.wake = null }
  }

  stored() {
    try { return localStorage.getItem(VOICE_KEY) } catch { return null }
  }
}
