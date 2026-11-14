# The scoring model's data: every called shot as a training example, and how well
# the hand-written rules agree with the calls (the number a model has to beat).
# Run after every session, once every shot has a call:
#
#   bin/rails ml:update               # ALL OF IT: export, compare (saved), retrain, recap
#   bin/rails ml:eval                 # export, then the baseline report
#   bin/rails ml:export               # just the export
#   bin/rails ml:eval SAVE=1          # also append the result to eval-history.jsonl
#   bin/rails ml:train                # export, then retrain the hole locator (STEPS=...)
#
# OUT=dir (default engine/out/ml/dataset, not in git: the pictures are the
# shooter's), LOGIN=username for one user's shots only (else everyone but demo).
namespace :ml do
  def ml_dataset_dir = ENV.fetch("OUT", EngineRunner.engine_dir.join("out/ml/dataset").to_s)

  desc "Export every called shot (close-ups + labels) for the scoring model"
  task export: :environment do
    r = TrainingExport.new(dir: ml_dataset_dir, login: ENV["LOGIN"]).call
    puts "Exported #{r.exported} called shots to #{r.dir} " \
         "(#{r.images_written} pictures written, #{r.removed} removed" \
         "#{", #{r.without_closeups} without close-ups" if r.without_closeups.positive?})"
  end

  desc "Export, then measure the scoring rules against the shooter's calls"
  task eval: :export do
    args = [ "mleval.py", ml_dataset_dir ]
    args << "--save" if ENV["SAVE"].present?
    system(EngineRunner.python, *args, chdir: EngineRunner.engine_dir.to_s, exception: true)
  end

  # ~15 min on the Studio's GPU at 60 shots (cross-validation trains one model per
  # held-out card/session). The engine picks the new model up at its next start.
  desc "Export, then retrain the hole locator (engine/ml; needs engine/ml/setup.sh once)"
  task train: :export do
    engine = EngineRunner.engine_dir
    python = engine.join("ml/.venv/bin/python")
    abort "No training environment: run engine/ml/setup.sh first" unless python.exist?
    args = [ "ml/train.py", ml_dataset_dir ]
    args += [ "--steps", ENV["STEPS"] ] if ENV["STEPS"].present?
    system(python.to_s, *args, chdir: engine.to_s, exception: true)
  end

  # The after-session routine in one go (the shooter's choice: a terminal command,
  # not a button on the web): export every call, compare the engine and the model
  # with them (the report, saved to the history), retrain (~15 min, full speed: the
  # shooter runs it with nothing else going on), then a
  # short recap of the latest session and the new model.
  desc "After a session: export, compare engine and model with your calls, retrain, recap"
  task update: :environment do
    abort "A session is running (#{EngineRunner.running.title}) - update the model after it." if EngineRunner.running
    engine = EngineRunner.engine_dir
    ml_python = engine.join("ml/.venv/bin/python")
    abort "No training environment: run engine/ml/setup.sh first" unless ml_python.exist?

    # Shots without a call are left out, not wrong - but say so, in case the
    # review isn't finished.
    unreviewed = Shot.joins(card: { practice_session: :user }).where(status: "scored", called_at: nil)
                     .where.not(users: { username: TrainingExport::DEMO_USER })
                     .where.not(practice_sessions: { ended_at: nil })
                     .group("practice_sessions.id").count
    if unreviewed.any?
      PracticeSession.where(id: unreviewed.keys).newest_first.first(5).each do |session|
        puts "Not reviewed yet: #{unreviewed[session.id]} shot(s) in #{session.title} - left out until called"
      end
    end

    Rake::Task["ml:export"].invoke
    system(EngineRunner.python, "mleval.py", ml_dataset_dir, "--save", chdir: engine.to_s, exception: true)
    puts "Retraining (about 15 minutes)..."
    system(ml_python.to_s, "ml/train.py", ml_dataset_dir,
           *ENV["STEPS"].presence&.then { [ "--steps", it ] }, chdir: engine.to_s, exception: true)

    summary = JSON.parse(engine.join("out/ml/eval-history.jsonl").readlines.last)
    meta = JSON.parse(engine.join("out/ml/model/hole.json").read)
    latest = summary["per_session"].max_by { [ it["date"], it["session_id"] ] }
    session = PracticeSession.find_by(id: latest["session_id"])
    puts
    puts "=" * 72
    puts "LATEST SESSION: #{session&.title || "##{latest["session_id"]}"}"
    puts "  rings that matched your calls: engine #{latest["agree"]} of #{latest["n"]}" +
         (latest["model_n"].to_i.positive? ? ", model #{latest["model_agree"]} of #{latest["model_n"]} (live, before it saw them)"
                                            : " (the model wasn't running in this session)")
    model = summary.dig("ring", "model")
    if model && model["n"].to_i.positive?
      rules = summary.dig("ring", "rules")
      puts "ALL SESSIONS, live: engine #{rules["agree"]} of #{rules["n"]}, model #{model["agree"]} of #{model["n"]}"
    end
    cv = meta["cv"]
    puts "NEW MODEL #{meta["version"]}: trained on #{meta["trained_on"]} called shots" +
         (cv ? "; on #{cv["by"]}s it hadn't seen: engine #{cv["rules_agree"]} of #{cv["n"]}, model #{cv["model_agree"]} of #{cv["n"]}" : "")
    puts "  Your next session uses it (shadow: the engine's rules still score)."
    puts "=" * 72
  end
end
