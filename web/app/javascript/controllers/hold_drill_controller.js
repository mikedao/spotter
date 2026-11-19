import { Controller } from "@hotwired/stimulus"

// The guided hold drill: for each hold, a few seconds to raise and settle, the
// hold itself, then a rest with the gun down. A big countdown, a tone at each
// change (made here, no sound files) and, if wanted, the browser's own voice.
// "Let down" ends a hold early and counts it as let down; "Stop" ends the drill.
// At the end the page submits what it saw (holds held, let downs, seconds held)
// to HoldDrillsController#create. The clock is the page's own, and runs on
// elapsed time so a slow timer tick never stretches a hold.
//
// The cues are spoken in the shooter's Kokoro voice: short pieces (raise, hold,
// lower, rest, three, two, one, done), exported ahead for every voice or rendered
// by the server on first use, fetched before the first hold and played through
// WebAudio on top of the tones. A cue that could not be fetched (Kokoro not set
// up and not exported) falls back to the browser's own voice.
const VOICE_KEY = "holdDrillVoice"
const TICK_MS = 100
const CUE_LOAD_S = 4   // wait this long for the voice before starting without it

export default class extends Controller {
  static targets = [ "rep", "phase", "count", "dots", "start", "pause", "letDown", "stop", "voice", "form", "repsDone", "letDowns", "heldSeconds" ]
  static values = { reps: Number, hold: Number, rest: Number, settle: Number, indexUrl: String, cues: Object }

  connect() {
    this.running = false
    this.sources = []
    this.cueBuffers = new Map()   // cue -> decoded audio, for the cues that loaded
    this.voiceTarget.checked = this.storedVoice() !== "off"
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
    this.phases = []
    for (let rep = 0; rep < this.repsValue; rep++) {
      this.phases.push({ kind: "settle", rep, secs: this.settleValue }, { kind: "hold", rep, secs: this.holdValue })
      if (rep < this.repsValue - 1) this.phases.push({ kind: "rest", rep, secs: this.restValue })
    }
    this.done = 0
    this.letDowns = 0
    this.held = 0
    this.outcomes = []            // per rep: "held" | "let down"
    this.running = true
    this.paused = false
    this.buildDots()
    this.startTarget.hidden = true
    this.pauseTarget.hidden = this.stopTarget.hidden = false
    this.starting = false
    this.enter(0, 0)
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

  // End this hold early: it counts as let down, and the rest begins.
  letDown() {
    if (!this.running || this.paused || this.phase.kind !== "hold") return
    this.letDowns += 1
    this.held += Math.min(this.elapsed, this.phase.secs)
    this.outcomes[this.phase.rep] = "let down"
    this.advance(this.index + 1, 0)
  }

  // End the drill now. Whatever was held so far is kept.
  stop() {
    if (!this.running) return
    if (this.phase.kind === "hold") this.held += Math.min(this.elapsed, this.phase.secs)
    this.finish()
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
    // Carry the overshoot into the next phase, so a late tick loses no time.
    while (this.running && this.elapsed >= this.phase.secs) {
      const over = this.elapsed - this.phase.secs
      if (this.phase.kind === "hold") {
        this.done += 1
        this.held += this.phase.secs
        this.outcomes[this.phase.rep] = "held"
      }
      this.advance(this.index + 1, over)
    }
    if (this.running) this.render()
  }

  advance(next, carry) {
    if (next >= this.phases.length) return this.finish()
    this.enter(next, carry)
  }

  enter(index, carry) {
    this.index = index
    this.phase = this.phases[index]
    this.elapsed = carry
    this.shown = null
    this.letDownTarget.hidden = this.phase.kind !== "hold"
    this.cue(this.phase.kind)
    this.render()
  }

  // The last rep's hold ends the drill: there is no rest after it.
  finish() {
    this.teardown()
    this.running = false
    this.cue("done")
    this.pauseTarget.hidden = this.letDownTarget.hidden = this.stopTarget.hidden = true
    if (this.done + this.letDowns === 0) return window.Turbo.visit(this.indexUrlValue)
    this.phaseTarget.textContent = "Saving…"
    this.repsDoneTarget.value = this.done
    this.letDownsTarget.value = this.letDowns
    this.heldSecondsTarget.value = this.held.toFixed(1)
    // Let "done" be heard before the page moves on.
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
    this.countTarget.dataset.phase = this.phase.kind
    this.repTarget.textContent = `Hold ${this.phase.rep + 1} of ${this.repsValue}`
    if (!this.paused) this.phaseTarget.textContent = this.label(this.phase)
    if (this.phase.kind === "rest" && remaining <= 3 && remaining > 0 && remaining !== this.shown) this.countdown(remaining)   // the next hold is coming
    this.shown = remaining
    this.paintDots()
  }

  label(phase) {
    return { settle: "Raise and settle", hold: "Hold", rest: "Rest. Gun down." }[phase.kind]
  }

  // A tone for the change, then the spoken cue after it.
  cue(kind) {
    const tones = { settle: [ [ 523 ], 0.15 ], hold: [ [ 880 ], 0.3 ], rest: [ [ 880, 660 ], 0.12 ], done: [ [ 523, 659, 784 ], 0.14 ] }[kind]
    const end = this.beep(...tones)
    this.speak({ settle: [ "raise" ], hold: [ "hold" ], rest: [ "lower", "rest" ], done: [ "done" ] }[kind], end)
  }

  // The last three seconds of a rest: counted aloud, or ticked without a voice.
  countdown(remaining) {
    const word = { 3: "three", 2: "two", 1: "one" }[remaining]
    if (this.voiceTarget.checked && this.cueBuffers.has(word)) this.speak([ word ], this.ctx.currentTime)
    else this.beep([ 660 ], 0.05)
  }

  // Say these cues, one after the other from `at`: in the shooter's voice, or the
  // browser's own for any that are missing.
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

  // Fetch and decode every cue before the first hold; whatever has not arrived
  // in CUE_LOAD_S is left to the browser's voice.
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

  buildDots() {
    this.dotsTarget.replaceChildren(...Array.from({ length: this.repsValue }, () => {
      const dot = document.createElement("span")
      dot.className = "size-4 rounded-full border-2 border-gray-400"
      return dot
    }))
  }

  paintDots() {
    Array.from(this.dotsTarget.children).forEach((dot, i) => {
      const outcome = this.outcomes[i]
      const current = i === this.phase.rep
      dot.className = "size-4 rounded-full border-2 " + (
        outcome === "held" ? "border-green-600 bg-green-600" :
        outcome === "let down" ? "border-red-600 bg-red-600" :
        current ? "border-blue-600 bg-blue-200 dark:bg-blue-900" : "border-gray-400")
    })
  }

  // A screen that sleeps mid-hold ends the drill.
  async keepAwake() {
    if (this.wake || !navigator.wakeLock) return
    try {
      this.wake = await navigator.wakeLock.request("screen")
      this.wake.addEventListener("release", () => { this.wake = null })
    } catch { this.wake = null }
  }

  storedVoice() {
    try { return localStorage.getItem(VOICE_KEY) } catch { return null }
  }
}
