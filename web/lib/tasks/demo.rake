# A replay of a real ten-shot card, scored live by the real engine, so you can
# watch the range screen fill up without a camera or a gun.
#
#   bin/dev                                  # the web app must be running
#   bin/rails spotter:demo                   # as a "Demo" user (username and PIN printed)
#   bin/rails spotter:demo LOGIN=you            # into your own account instead
#
# It sets the session up on the clean card, prints the range screen's link and
# WAITS: open the link, start recording, then press Enter to start the shots.
# The first shot lands DEMO_FIRST seconds after Enter (default 3; the clean card
# is already the baseline, so only the gaps BETWEEN shots need DEMO_EVERY).
# DEMO_WAIT=0 starts them at once (scripts).
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
    demo = engine.join("out/shots/demo")
    frames = [ demo.join("044_before.png") ] + shots.map { demo.join("#{it}_after.png") }
    missing = frames.reject(&:exist?)
    abort "The demo replays engine/out/shots/demo (shots 044-053), which aren't here: #{missing.first}" if missing.any?

    user = if ENV["LOGIN"].present?
      User.find_by!(username: ENV["LOGIN"].strip.downcase)
    else
      User.find_or_create_by!(username: "demo") { it.name = "Demo"; it.email_address = "demo@spotter.local"; it.pin = "1010" }
    end

    port = ENV.fetch("DEMO_STREAM_PORT", "8095")
    # Without a microphone the engine needs two camera checks (2 s apart) plus
    # scoring per shot: faster than ~7 s, two new holes land in one comparison
    # and one is lost (a 5 s demo scored 6 of 10). 7 s only works on an idle
    # machine: with Spotlight indexing, geometry solves ran 1.7x slow and 7 s
    # scored 6-9 of 10. Default 10 s for slack.
    every = [ ENV.fetch("DEMO_EVERY", "10").to_f, 7.0 ].max.to_s
    first = ENV.fetch("DEMO_FIRST", "3")
    out = Dir.mktmpdir("spotter-demo")
    stream = Process.spawn(EngineRunner.python, "camstream.py", "--port", port, "--every", every,
                           "--hold", "--first", first, "--playlist", *frames.map(&:to_s), chdir: engine.to_s, out: File::NULL, err: File::NULL)
    sleep 3

    session = EngineRunner.start!(user:, target: "pistol", per_card: 10, camera: "http://127.0.0.1:#{port}/stream",
                                  mic: "none", env: { "SPOTTER_OUT" => out })
    session.update!(notes: "Demo: replay of a real ten-shot card (shots 044-053)")
    puts "Demo session started for #{user.name}; waiting for the engine to find the card..."
    60.times { break if session.reload.status != "starting" || !EngineRunner.alive?(session); sleep 1 }
    abort "The engine stopped: #{session.reload.engine_error}" unless EngineRunner.alive?(session)

    puts
    puts "  Open:  #{EngineRunner.web_url}/practice/#{session.id}"
    puts "  (sign in as demo, PIN 1010)" if ENV["LOGIN"].blank?
    puts
    if ENV.fetch("DEMO_WAIT", "1") != "0"
      print "Status: #{session.status}. Start recording, then press Enter to fire the first shot... "
      $stdin.gets
    end
    Process.kill("USR1", stream)
    puts "Shooting: first shot in #{first.to_f.round} s, then one every #{every.to_f.round} s (#{frames.size - 1} shots)."

    seconds = frames.size * every.to_f + 25
    deadline = Time.current + seconds
    sleep 1 while Time.current < deadline && EngineRunner.alive?(session.reload)
    EngineRunner.stop!(session)
    15.times { break unless EngineRunner.alive?(session); sleep 1 }
    puts "Done: #{session.reload.shots.where(status: 'scored').count} shots scored."
  ensure
    # Ctrl+C (e.g. at the prompt) or an error: don't leave the engine running.
    EngineRunner.stop!(session) if session && EngineRunner.alive?(session.reload) rescue nil
    Process.kill("TERM", stream) if stream rescue nil
    FileUtils.rm_rf(out) if out
  end
end
