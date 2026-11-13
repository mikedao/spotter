# The scoring model's data: every called shot as a training example, and how well
# the hand-written rules agree with the calls (the number a model has to beat).
# Run after every session:
#
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
end
