// The BROWSER as the shot trigger (2026-11-13): the device showing the range
// screen (the laptop at the firing line) listens for the gun, and each sharp
// sound goes to the engine through the web app (POST /practice/:id/trigger).
//
// The detector is engine/audio.py's EventDetector, ported line for line: the
// envelope is the peak |sample| per 2 ms, the floor the median envelope of the
// last 3 s of non-event audio, a sound starts 20 dB over the floor and ends after
// 25 ms below it. It runs on the browser's AUDIO thread (an AudioWorklet), so a
// background tab or a busy page can't make it miss a shot.
//
// The browser's own processing is turned OFF (echo cancellation, noise
// suppression, automatic gain): each squashes a gunshot's attack. Microphone
// access needs https (or localhost): bin/rails spotter:tls.
//
//   const l = new ShotListener({ onSound, onLevel, onState })
//   l.start()        // asks for the microphone; may wait for a tap (browsers' rule)
//   l.stop()
//
// onSound({ over_db, len_ms, ago_ms }) - ago_ms = how long ago it BEGAN, so
// the engine can time it on its own clock. onLevel({ peak_dbfs, floor_dbfs,
// over_db }) four times a second. onState("starting" | "listening" |
// "needs-tap" | "denied" | "insecure" | "unsupported" | "failed", detail).

const WORKLET = `
const ENV_MS = 2.0, MERGE_MS = 25.0, FLOOR_S = 3.0
const dbfs = (x) => 20 * Math.log10(Math.max(x, 1e-9))

class ShotDetector extends AudioWorkletProcessor {
  constructor(options) {
    super()
    const ratioDb = options.processorOptions.ratioDb
    this.win = Math.max(1, Math.floor(sampleRate * ENV_MS / 1000))
    this.ratio = 10 ** (ratioDb / 20)
    this.max = Math.floor(FLOOR_S * 1000 / ENV_MS)
    this.ring = new Float32Array(this.max); this.n = 0; this.head = 0   // last 3 s, in order of arrival
    this.sorted = []                                                    // the same values, sorted: exact median
    this.acc = 0; this.k = 0
    this.t = 0; this.t0 = null                                           // seconds of audio consumed
    this.cur = null; this.quiet = 0
    this.levelPeak = 0; this.levelEvery = Math.floor(sampleRate / 4); this.levelK = 0
  }

  insert(v) {
    let lo = 0, hi = this.sorted.length
    while (lo < hi) { const m = (lo + hi) >> 1; if (this.sorted[m] < v) lo = m + 1; else hi = m }
    this.sorted.splice(lo, 0, v)
  }

  remove(v) {
    let lo = 0, hi = this.sorted.length
    while (lo < hi) { const m = (lo + hi) >> 1; if (this.sorted[m] < v) lo = m + 1; else hi = m }
    this.sorted.splice(lo, 1)
  }

  push(v) {                     // deque(maxlen=...).append
    if (this.n === this.max) { this.remove(this.ring[this.head]); this.n-- }
    this.ring[this.head] = v; this.head = (this.head + 1) % this.max; this.n++
    this.insert(v)
  }

  floor() {                     // np.median, after 0.5 s
    const n = this.sorted.length
    if (n < Math.floor(500 / ENV_MS)) return null
    const med = n % 2 ? this.sorted[(n - 1) >> 1] : (this.sorted[n / 2 - 1] + this.sorted[n / 2]) / 2
    return Math.max(med, 1e-5)
  }

  envelope(v) {
    const fl = this.floor()
    const hot = fl !== null && v > fl * this.ratio
    if (hot) {
      if (this.cur === null) this.cur = { t: this.t, peak: v, floor: fl }
      this.cur.peak = Math.max(this.cur.peak, v)
      this.quiet = 0
    } else {
      this.push(v)
      if (this.cur !== null) {
        this.quiet += ENV_MS
        if (this.quiet >= MERGE_MS) {
          const e = this.cur
          this.port.postMessage({ type: "sound", start: this.t0 + e.t,
            len_ms: (this.t - e.t) * 1000 - this.quiet, over_db: dbfs(e.peak) - dbfs(e.floor) })
          this.cur = null
        }
      }
    }
    this.t += ENV_MS / 1000
  }

  process(inputs) {
    const chans = inputs[0]
    if (!chans || chans.length === 0) return true
    if (this.t0 === null) this.t0 = currentTime
    const len = chans[0].length
    for (let i = 0; i < len; i++) {
      let s = 0
      for (let c = 0; c < chans.length; c++) s += chans[c][i]
      const a = Math.abs(s / chans.length)             // indata.mean(axis=1)
      if (a > this.acc) this.acc = a
      if (a > this.levelPeak) this.levelPeak = a
      if (++this.k === this.win) { this.envelope(this.acc); this.acc = 0; this.k = 0 }
      if (++this.levelK === this.levelEvery) {
        const fl = this.floor()
        this.port.postMessage({ type: "level", peak_dbfs: dbfs(this.levelPeak), floor_dbfs: fl === null ? null : dbfs(fl) })
        this.levelPeak = 0; this.levelK = 0
      }
    }
    return true
  }
}
registerProcessor("shot-detector", ShotDetector)
`

// The detector itself, for checking it against the engine's on a recording
// (an OfflineAudioContext plays a file through it).
export const DETECTOR = WORKLET

export default class ShotListener {
  constructor({ onSound = () => {}, onLevel = () => {}, onState = () => {}, ratioDb = 20 } = {}) {
    Object.assign(this, { onSound, onLevel, onState, ratioDb })
    this.unlock = () => this.resume()
  }

  async start() {
    if (!window.isSecureContext) return this.onState("insecure")
    if (!navigator.mediaDevices?.getUserMedia || !window.AudioWorkletNode) return this.onState("unsupported")
    this.onState("starting")
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false }
      })
    } catch (error) {
      return this.onState(error.name === "NotAllowedError" ? "denied" : "failed", error.message)
    }
    try {
      this.ctx = new AudioContext()
      const url = URL.createObjectURL(new Blob([ WORKLET ], { type: "text/javascript" }))
      await this.ctx.audioWorklet.addModule(url)
      URL.revokeObjectURL(url)
      this.node = new AudioWorkletNode(this.ctx, "shot-detector",
        { numberOfInputs: 1, numberOfOutputs: 0, processorOptions: { ratioDb: this.ratioDb } })
      this.node.port.onmessage = ({ data }) => this.message(data)
      this.ctx.createMediaStreamSource(this.stream).connect(this.node)
      this.ctx.onstatechange = () => this.report()
      this.stream.getAudioTracks()[0]?.addEventListener("ended", () => this.onState("failed", "the microphone went away"))
    } catch (error) {
      return this.onState("failed", error.message)
    }
    this.resume()
  }

  // Browsers run audio only once the page has had a tap or key press.
  resume() {
    this.ctx?.resume()
    this.report()
  }

  report() {
    if (!this.ctx) return
    if (this.ctx.state === "running") {
      document.removeEventListener("pointerdown", this.unlock, true)
      document.removeEventListener("keydown", this.unlock, true)
      this.keepAwake()
      this.onState("listening")
    } else if (this.ctx.state === "suspended") {
      document.addEventListener("pointerdown", this.unlock, true)
      document.addEventListener("keydown", this.unlock, true)
      this.onState("needs-tap")
    }
  }

  message(data) {
    if (data.type === "sound") {
      const ago_ms = Math.max(0, (this.ctx.currentTime - data.start) * 1000)
      this.onSound({ over_db: data.over_db, len_ms: Math.max(0, data.len_ms), ago_ms })
    } else if (data.type === "level") {
      const over = data.floor_dbfs === null ? null : data.peak_dbfs - data.floor_dbfs
      this.onLevel({ peak_dbfs: data.peak_dbfs, floor_dbfs: data.floor_dbfs, over_db: over })
    }
  }

  // A sleeping laptop hears nothing: hold the screen on while listening.
  async keepAwake() {
    if (this.wake || !navigator.wakeLock) return
    try {
      this.wake = await navigator.wakeLock.request("screen")
      this.wake.addEventListener("release", () => { this.wake = null })
    } catch { this.wake = null }
  }

  stop() {
    document.removeEventListener("pointerdown", this.unlock, true)
    document.removeEventListener("keydown", this.unlock, true)
    this.node?.port && (this.node.port.onmessage = null)
    this.stream?.getTracks().forEach((t) => t.stop())
    this.ctx?.close()
    this.wake?.release()
    this.ctx = this.stream = this.node = this.wake = null
  }
}
