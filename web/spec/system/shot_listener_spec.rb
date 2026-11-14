require "rails_helper"

# The browser's shot detector (lib/shot_listener.js) is engine/audio.py's
# EventDetector ported: on the same recording it must hear what the engine hears.
# spec/fixtures/files/shot.wav is a real shot (the rig's `listen`, 2026-11); the
# engine's detector finds one sound in it: at 2.34 s, +62.7 dB, 242 ms. Played
# through the browser's detector offline (no microphone), the same.
RSpec.describe "The browser's shot detector" do
  it "hears a recorded shot exactly as the engine does" do
    visit new_session_path   # any page: the import map is there
    wav = Base64.strict_encode64(file_fixture("shot.wav").binread)
    events = page.evaluate_async_script(<<~JS, wav)
      const [ b64, done ] = arguments
      ;(async () => {
        const { DETECTOR } = await import("lib/shot_listener")
        const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
        const buf = await new OfflineAudioContext(1, 1, 48000).decodeAudioData(bytes.buffer)
        const ctx = new OfflineAudioContext(1, buf.length + 48000, buf.sampleRate)
        await ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([ DETECTOR ], { type: "text/javascript" })))
        const node = new AudioWorkletNode(ctx, "shot-detector", { numberOfOutputs: 1, processorOptions: { ratioDb: 20 } })
        const events = []
        node.port.onmessage = ({ data }) => { if (data.type === "sound") events.push(data) }
        const src = ctx.createBufferSource()
        src.buffer = buf
        src.connect(node); node.connect(ctx.destination); src.start()
        await ctx.startRendering()
        setTimeout(() => done(events), 300)   // the last messages
      })().catch((e) => done(String(e)))
    JS

    expect(events).to be_an(Array)
    expect(events.size).to eq(1)
    expect(events.first).to include("start" => be_within(0.005).of(2.34), "over_db" => be_within(0.05).of(62.7),
                                    "len_ms" => be_within(1).of(242))
  end
end
