import { Controller } from "@hotwired/stimulus"

// The range screen's announcer: plays each announcement the engine makes, ONE
// at a time - a short tone for the kind of news, then the voice, piece by piece
// with real silence between (longer between sentences, shorter at commas: the
// shooter asked for clear pauses). Browsers only play sound after a tap, so it
// starts off: "Sound on". Pieces come from the server (VoicesController#piece)
// and are kept for the visit; without Kokoro it falls back to the browser's own
// voice. Tones are made here, no sound files.
export default class extends Controller {
  static targets = [ "button" ]

  connect() {
    this.on = false
    this.queue = []
    this.playing = false
    this.buffers = new Map()
    this.listener = (event) => this.enqueue(event.detail)
    window.addEventListener("announcer:say", this.listener)
    this.render()
  }

  disconnect() {
    window.removeEventListener("announcer:say", this.listener)
    this.queue = []
    this.ctx?.close()
  }

  toggle() {
    this.on = !this.on
    if (this.on) {
      this.ctx ||= new AudioContext()
      this.ctx.resume()
      this.tone("ready")
    } else {
      this.queue = []
    }
    this.render()
  }

  render() {
    this.buttonTarget.textContent = this.on ? "🔊 Sound on" : "🔇 Sound off"
    this.buttonTarget.title = this.on ? "Announcements play here. Tap to mute." : "Tap to hear the announcer on this screen"
    this.buttonTarget.setAttribute("aria-pressed", String(this.on))
    this.element.dataset.on = String(this.on)
  }

  enqueue(announcement) {
    if (!this.on) return
    this.queue.push(announcement)
    if (!this.playing) this.next()
  }

  async next() {
    const announcement = this.queue.shift()
    if (!announcement) { this.playing = false; return }
    this.playing = true
    try { await this.play(announcement) } catch (error) { console.warn("announcer:", error) }
    this.element.dataset.played = Number(this.element.dataset.played || 0) + 1   // how many so far (specs read it)
    this.next()
  }

  async play(a) {
    if (a.kind !== "ro") await this.tone(a.kind)
    if (!a.kokoro) return this.speakWithBrowser(a)

    // Fetch every piece first (most are cached), then schedule them gap-exact.
    const sentences = await Promise.all(a.sentences.map((pieces) =>
      Promise.all(pieces.map(([ , url ]) => this.buffer(url).catch(() => null)))))
    let at = this.ctx.currentTime + 0.05
    sentences.forEach((buffers, i) => {
      if (i) at += a.gaps.sentence
      buffers.filter(Boolean).forEach((buffer, j) => {
        if (j) at += a.gaps.comma
        const source = this.ctx.createBufferSource()
        source.buffer = buffer
        source.connect(this.ctx.destination)
        source.start(at)
        at += buffer.duration
      })
    })
    await this.wait(at - this.ctx.currentTime)
  }

  buffer(url) {
    if (!this.buffers.has(url)) {
      const loading = fetch(url)
        .then((response) => { if (!response.ok) throw new Error(`${response.status} ${url}`); return response.arrayBuffer() })
        .then((data) => this.ctx.decodeAudioData(data))
      loading.catch(() => this.buffers.delete(url))   // try again next time
      this.buffers.set(url, loading)
    }
    return this.buffers.get(url)
  }

  // Without Kokoro: the browser's own voice, a sentence at a time.
  speakWithBrowser(a) {
    return new Promise((resolve) => {
      if (!("speechSynthesis" in window)) return resolve()
      const sentences = a.sentences.map((pieces) => pieces.map(([ text ]) => text).join(", "))
      sentences.forEach((text, i) => {
        const utterance = new SpeechSynthesisUtterance(text)
        if (i === sentences.length - 1) utterance.onend = resolve
        speechSynthesis.speak(utterance)
      })
    })
  }

  // ok: one high note; check: high then lower (worth a look); fail: one low
  // note; ready: rising; info: one middle note.
  tone(kind) {
    const notes = { ok: [ 880 ], check: [ 880, 660 ], fail: [ 220 ], ready: [ 523, 784 ], info: [ 660 ] }[kind]
    if (!notes || !this.ctx) return Promise.resolve()
    const length = kind === "fail" ? 0.35 : 0.12
    let at = this.ctx.currentTime + 0.02
    notes.forEach((frequency) => {
      const oscillator = this.ctx.createOscillator()
      const gain = this.ctx.createGain()
      oscillator.frequency.value = frequency
      gain.gain.setValueAtTime(0.0001, at)
      gain.gain.exponentialRampToValueAtTime(0.2, at + 0.01)
      gain.gain.exponentialRampToValueAtTime(0.0001, at + length)
      oscillator.connect(gain).connect(this.ctx.destination)
      oscillator.start(at)
      oscillator.stop(at + length + 0.02)
      at += length + 0.04
    })
    return this.wait(at - this.ctx.currentTime + 0.15)
  }

  wait(seconds) {
    return new Promise((resolve) => setTimeout(resolve, Math.max(seconds, 0) * 1000))
  }
}
