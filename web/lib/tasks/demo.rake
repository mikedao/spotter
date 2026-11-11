# A replay of a real ten-shot card, scored live by the real engine, so you can
# watch the range screen fill up without a camera or a gun.
#
#   bin/dev                                  # the web app must be running
#   bin/rails spotter:demo                   # as a "Demo" user (password printed)
#   bin/rails spotter:demo EMAIL=you@example.com   # into your own account instead
#
# camstream.py serves the card's photos in turn (the clean card, then the card
# after each shot) as if a camera were watching; the engine runs with no
# microphone, so its camera check finds each new hole. Shots, frames and the
# shot log go to a temporary folder (SPOTTER_OUT), never the real engine/out.
namespace :spotter do
  desc "Replay a real ten-shot card through the engine and web app (bin/dev must be running)"
  task demo: :environment do
    $stdout.sync = true
    engine = EngineRunner.engine_dir
    shots = (44..53).map { format("%03d", it) }
    frames = [ engine.join("out/shots/044_before.png") ] + shots.map { engine.join("out/shots/#{it}_after.png") }
    missing = frames.reject(&:exist?)
    abort "The demo replays engine/out/shots/044-053, which aren't here: #{missing.first}" if missing.any?

    user = if ENV["EMAIL"].present?
      User.find_by!(email_address: ENV["EMAIL"].strip.downcase)
    else
      User.find_or_create_by!(email_address: "demo@spotter.local") { it.name = "Demo"; it.password = "spotter-demo" }
    end

    port = ENV.fetch("DEMO_STREAM_PORT", "8095")
    # Without a microphone the engine needs two camera checks (2 s apart) plus
    # scoring per shot: faster than ~7 s, two new holes land in one comparison
    # and one is lost (a 5 s demo scored 6 of 10). 7 s only works on an idle
    # machine: with Spotlight indexing, geometry solves ran 1.7x slow and 7 s
    # scored 6-9 of 10. Default 10 s for slack.
    every = [ ENV.fetch("DEMO_EVERY", "10").to_f, 7.0 ].max.to_s
    out = Dir.mktmpdir("spotter-demo")
    stream = Process.spawn(EngineRunner.python, "camstream.py", "--port", port, "--every", every,
                           "--playlist", *frames.map(&:to_s), chdir: engine.to_s, out: File::NULL, err: File::NULL)
    sleep 3

    session = EngineRunner.start!(user:, target: "pistol", per_card: 10, camera: "http://127.0.0.1:#{port}/stream",
                                  mic: "none", env: { "SPOTTER_OUT" => out })
    session.update!(notes: "Demo: replay of a real ten-shot card (shots 044-053)")
    puts "Demo session started for #{user.name}."
    puts "Watch it live: #{EngineRunner.web_url}/practice/#{session.id}"
    puts "(sign in as demo@spotter.local / spotter-demo)" if ENV["EMAIL"].blank?

    seconds = frames.size * every.to_f + 25
    deadline = Time.current + seconds
    sleep 1 while Time.current < deadline && EngineRunner.alive?(session.reload)
    EngineRunner.stop!(session)
    15.times { break unless EngineRunner.alive?(session); sleep 1 }
    puts "Done: #{session.reload.shots.where(status: 'scored').count} shots scored."
  ensure
    Process.kill("TERM", stream) if stream rescue nil
    FileUtils.rm_rf(out) if out
  end
end
