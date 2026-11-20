import { Controller } from "@hotwired/stimulus"

// The timed-fire timer (Pardini dry fire). For each string: "ready" and a short
// random wait (so the start can't be anticipated), a beep, then the string's seconds
// to fire its shots - with an optional soft tick at each shot's share of the time,
// to keep the pace smooth - a stop beep, and a rest (none after the last string).
// Tones are made here (no sound files); the cues (ready, stop, rest, three, two, one,
// done) are spoken in the shooter's Kokoro voice, fetched before the first string
// and played through WebAudio, falling back to the browser's voice for any missing.
// The clock runs on elapsed time with overshoot carried, as the hold drill's does.
// At the end the page submits how many strings ran to the stop to TimedDrillsController#create.
const VOICE_KEY = "timedDrillVoice"
const PACE_KEY = "timedDrillPace"
const TICK_MS = 100
const CUE_LOAD_S = 4

export default class extends Controller {
  static targets = [ "string", "phase", "count", "shot", "dots", "start", "pause", "stop", "voice", "pace", "form", "stringsDone" ]
  static values = { strings: Number, shots: Number, seconds: Number, rest: Number, readyMin: Number, readyMax: Number, indexUrl: String, cues: Object }

  connect() {
    this.running = false
    this.sources = []
    this.cueBuffers = new Map()
    this.voiceTarget.checked = this.stored(VOICE_KEY) !== "off"
    this.paceTarget.checked = this.stored(PACE_KEY) !== "off"
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
    for (let n = 0; n < this.stringsValue; n++) {
      const wait = this.readyMinValue + Math.random() * (this.readyMaxValue - this.readyMinValue)
      this.phases.push({ kind: "ready", n, secs: wait }, { kind: "fire", n, secs: this.secondsValue })
      if (n < this.stringsValue - 1) this.phases.push({ kind: "rest", n, secs: this.restValue })
    }
    this.done = 0
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

  // End now. A string stopped before its stop beep does not count.
  stop() {
    if (this.running) this.finish()
  }

  rememberChoices() {
    try {
      localStorage.setItem(VOICE_KEY, this.voiceTarget.checked ? "on" : "off")
      localStorage.setItem(PACE_KEY, this.paceTarget.checked ? "on" : "off")
    } catch { /* private window */ }
    if (!this.voiceTarget.checked) window.speechSynthesis?.cancel()
  }

  tick() {
    const now = performance.now()
    const dt = (now - this.last) / 1000
    this.last = now
    if (this.paused) return
    this.elapsed += dt
    while (this.running && this.elapsed >= this.phase.secs) {
      const over = this.elapsed - this.phase.secs
      if (this.phase.kind === "fire") this.done += 1
      this.advance(this.index + 1, over)
    }
    if (this.running) this.render()
  }

  advance(next, carry) {
    if (next >= this.phases.length) return this.finish()
    this.enter(next, carry)
  }

  enter(index, carry) {
    const previous = this.phase
    this.index = index
    this.phase = this.phases[index]
    this.elapsed = carry
    this.shown = null
    this.nextTick = 1
    // The end of a string: the stop beep and word, then "rest" in the same breath
    // (a new cue would cut the first one off). Anything else gets its own cue.
    if (previous?.kind === "fire") this.cue("stop", [ "stop", "rest" ])
    else this.cue(this.phase.kind)
    this.render()
  }

  finish() {
    this.teardown()
    this.running = false
    if (this.phase?.kind === "fire" && this.done >= this.stringsValue) this.cue("stop", [ "stop", "done" ])
    else this.cue("done")
    this.pauseTarget.hidden = this.stopTarget.hidden = true
    if (this.done === 0) return window.Turbo.visit(this.indexUrlValue)
    this.phaseTarget.textContent = "Saving…"
    this.stringsDoneTarget.value = this.done
    setTimeout(() => this.formTarget.requestSubmit(), this.voiceTarget.checked ? 1400 : 400)
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
    const p = this.phase
    const remaining = Math.max(0, Math.ceil(p.secs - this.elapsed))
    this.stringTarget.textContent = `String ${p.n + 1} of ${this.stringsValue}`
    this.countTarget.dataset.phase = p.kind
    if (!this.paused) this.phaseTarget.textContent = this.label(p)
    if (p.kind === "ready") {
      this.countTarget.textContent = "•••"   // the wait is random: no countdown to anticipate
      this.shotTarget.innerHTML = "&nbsp;"
    } else {
      this.countTarget.textContent = remaining
      if (p.kind === "fire") {
        const slot = p.secs / this.shotsValue
        this.shotTarget.textContent = `Shot ${Math.min(this.shotsValue, Math.floor(this.elapsed / slot) + 1)} of ${this.shotsValue}`
        while (this.nextTick < this.shotsValue && this.elapsed >= this.nextTick * slot) {
          if (this.paceTarget.checked) this.beep([ 330 ], 0.04)
          this.nextTick += 1
        }
      } else {
        this.shotTarget.innerHTML = "&nbsp;"
      }
    }
    if (p.kind === "rest" && remaining <= 3 && remaining > 0 && remaining !== this.shown) this.countdown(remaining)
    this.shown = remaining
    this.paintDots()
  }

  label(phase) {
    return { ready: "Ready. Low ready, wait for the beep.", fire: "Fire", rest: "Rest. Gun down." }[phase.kind]
  }

  cue(kind, words = null) {
    const tones = { ready: [ [ 523 ], 0.15 ], fire: [ [ 988 ], 0.5 ], stop: [ [ 988, 659 ], 0.2 ], rest: [ [ 660 ], 0.1 ], done: [ [ 523, 659, 784 ], 0.14 ] }[kind]
    const end = this.beep(...tones)
    // The start beep is the command: no word over it.
    words ||= { ready: [ "ready" ], rest: [ "rest" ], done: [ "done" ] }[kind]
    if (words) this.speak(words, end)
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

  buildDots() {
    this.dotsTarget.replaceChildren(...Array.from({ length: this.stringsValue }, () => {
      const dot = document.createElement("span")
      dot.className = "size-4 rounded-full border-2 border-gray-400"
      return dot
    }))
  }

  paintDots() {
    Array.from(this.dotsTarget.children).forEach((dot, i) => {
      dot.className = "size-4 rounded-full border-2 " + (
        i < this.done ? "border-green-600 bg-green-600" :
        i === this.phase.n ? "border-blue-600 bg-blue-200 dark:bg-blue-900" : "border-gray-400")
    })
  }

  async keepAwake() {
    if (this.wake || !navigator.wakeLock) return
    try {
      this.wake = await navigator.wakeLock.request("screen")
      this.wake.addEventListener("release", () => { this.wake = null })
    } catch { this.wake = null }
  }

  stored(key) {
    try { return localStorage.getItem(key) } catch { return null }
  }
}
