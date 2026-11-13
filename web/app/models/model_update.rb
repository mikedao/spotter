# "Update the scoring model": the after-session routine as one button, offered on
# a finished session once every shot in it has a call (the shooter: review, then
# compare, then retrain - in that order). Three steps, run from a thread in the
# web process (so each step's progress reaches the page live, as the rig checks'
# do), state kept on the session (practice_sessions.model_update):
#
#   export   TrainingExport: every called shot -> engine/out/ml/dataset
#   compare  engine/mleval.py --save --json: the rules and the LIVE model (shadow
#            estimates made during this session, by a model trained before it)
#            against the calls; the history line is appended
#   train    engine/ml/train.py, niced (~15 min): cross-validates, retrains,
#            exports out/ml/model/hole.onnx - the engine loads it at its next start
#
# One update at a time (it loads the GPU), never while a session is live (the
# engine's scoring would slow). A server restart mid-update is noticed on the
# next page load (reconcile!) and the training process is stopped (at_exit).
class ModelUpdate
  class Busy < StandardError; end

  STEPS = { "export" => "Exporting your calls", "compare" => "Comparing the engine and the model with your calls",
            "train" => "Retraining the model" }.freeze
  THREADS = {}
  PIDS = {}
  MUTEX = Monitor.new   # reentrant: start! asks running -> reconcile! while holding it

  at_exit { PIDS.each_value { Process.kill("TERM", it) rescue nil } }

  class << self
    def engine_dir = EngineRunner.engine_dir
    def python = EngineRunner.python
    def ml_python = ENV.fetch("SPOTTER_ML_PYTHON", engine_dir.join("ml/.venv/bin/python").to_s)
    def dataset_dir = engine_dir.join("out/ml/dataset")
    def model_meta = engine_dir.join("out/ml/model/hole.json")

    # Every scored shot reviewed, the session over, not the demo replays.
    def ready?(session)
      !session.live? && session.user.username != TrainingExport::DEMO_USER &&
        scored(session).exists? && !scored(session).where(called_at: nil).exists?
    end

    def left_to_review(session) = scored(session).where(called_at: nil).count

    def running
      PracticeSession.where("json_extract(model_update, '$.status') = 'running'").find { reconcile!(it).running? }
    end

    def start!(session)
      raise Busy, "a session is running - update the model after it" if EngineRunner.running
      MUTEX.synchronize do
        other = running
        raise Busy, "an update is already running (#{other.title})" if other
        raise Busy, "every shot needs a call first" unless ready?(session)

        write(session, "status" => "running", "step" => "export", "started_at" => Time.current.iso8601,
                       "finished_at" => nil, "error" => nil, "result" => {})
        THREADS[session.id] = Thread.new { run(session) }
      end
    end

    # A "running" update with no thread in this process was cut off by a restart.
    def reconcile!(session)
      state = for_session(session)
      if state.running? && MUTEX.synchronize { !THREADS[session.id]&.alive? }
        write(session, state.to_h.merge("status" => "failed",
                                        "error" => "It stopped when the app restarted. Run it again."))
        state = for_session(session)
      end
      state
    end

    State = Data.define(:status, :step, :started_at, :finished_at, :error, :result) do
      def running? = status == "running"
      def done? = status == "done"
      def failed? = status == "failed"
      def step_label = STEPS[step]
      def to_h = super.transform_keys(&:to_s)
    end

    def for_session(session)
      h = session.model_update || {}
      State.new(status: h["status"], step: h["step"], started_at: h["started_at"], finished_at: h["finished_at"],
                error: h["error"], result: h["result"] || {})
    end

    private
      def scored(session) = Shot.joins(:card).where(cards: { practice_session_id: session.id }, status: "scored")

      def run(session)
        result = {}
        TrainingExport.new(dir: dataset_dir).call
        ActiveRecord::Base.connection_pool.release_connection

        step!(session, "compare", result)
        summary = JSON.parse(capture!(python, "mleval.py", dataset_dir.to_s, "--save", "--json"))
        result["session"] = summary["per_session"].find { it["session_id"] == session.id }
        result["overall"] = { "shots" => summary["shots"], "sessions" => summary["sessions"],
                              "rules" => summary.dig("ring", "rules").slice("agree", "n"),
                              "model" => summary.dig("ring", "model")&.slice("agree", "n") }

        step!(session, "train", result)
        raise "the training environment is missing: run engine/ml/setup.sh" unless File.executable?(ml_python)
        train!(session)
        meta = JSON.parse(model_meta.read)
        result["trained"] = meta.slice("version", "trained_on", "sessions", "cv")
        write(session, for_session(session).to_h.merge("status" => "done", "step" => nil, "result" => result,
                                                       "finished_at" => Time.current.iso8601))
      rescue StandardError => e
        write(session, for_session(session).to_h.merge("status" => "failed", "error" => e.message.truncate(300),
                                                       "finished_at" => Time.current.iso8601))
      ensure
        MUTEX.synchronize { THREADS.delete(session.id) }
        broadcast(session)
      end

      def step!(session, step, result)
        write(session, for_session(session).to_h.merge("step" => step, "result" => result))
      end

      def capture!(*argv)
        out, err, status = Open3.capture3(*argv, chdir: engine_dir.to_s)
        raise "#{File.basename(argv[1])} failed: #{last_line(err)}" unless status.success?

        out
      end

      def train!(session)
        log = Rails.root.join("log", "ml", "train-#{session.id}.log")
        log.dirname.mkpath
        pid = Process.spawn("nice", "-n", "10", ml_python, "ml/train.py", dataset_dir.to_s,
                            *ENV["SPOTTER_ML_STEPS"].presence&.then { [ "--steps", it ] },
                            chdir: engine_dir.to_s, out: log.to_s, err: [ :child, :out ])
        PIDS[session.id] = pid
        _, status = Process.wait2(pid)
        raise "training failed: #{last_line(log.read)}" unless status.success?
      ensure
        PIDS.delete(session.id)
      end

      def last_line(text) = text.to_s.lines.map(&:strip).reject { it.empty? || it.match?(/warning/i) }.last.to_s.truncate(200)

      # Each write gives its database connection back: the thread spends ~15 min
      # waiting on training and must not hold one of the pool's few meanwhile.
      def write(session, state)
        session.update_column(:model_update, state)
        broadcast(session)
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end

      def broadcast(session)
        Rails.application.executor.wrap do
          Turbo::StreamsChannel.broadcast_replace_to(session, target: "model_update",
                                                     renderable: ModelUpdateComponent.new(session: session.reload),
                                                     layout: false)
        end
      rescue StandardError => e
        Rails.logger.warn("model update broadcast: #{e.message}")
      end
  end
end
