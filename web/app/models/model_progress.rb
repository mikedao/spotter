# How the learned hole locator is coming along (the shooter, 2026-11-13: "as much
# information as possible to determine how well our model training is going").
# One row per trained model in engine/out/ml/progress.jsonl (not in git): what it
# learned from, how it did LIVE (estimates made during a session, before it saw
# those shots - the honest test) on the latest session and on every session it
# ran in, and its held-out check at training time - each beside the engine's
# rules. Shown by `bin/rails ml:progress` / ml:update, and on the Scoring model
# page (ScoringModelsController) with the latest live details.
#
#   ModelProgress.record!     # after a training: the current model's row (once per model)
#   ModelProgress.rows        # every row, oldest first
#   ModelProgress.summary     # the latest mleval summary (per session, head to head, calibration)
#   ModelProgress.readiness   # is it ready to score? in plain words, from the LIVE numbers
#   ModelProgress.table       # the rows as text
#
# Built from the latest mleval summary (eval-history.jsonl) and the model's
# metadata (model/hole.json, written by engine/ml/train.py).
class ModelProgress
  # Judge only on live results, and only after this many sessions of them.
  MIN_LIVE_SESSIONS = 3

  Readiness = Data.define(:state, :headline, :detail)

  class << self
    def dir = EngineRunner.engine_dir.join("out/ml")
    def path = dir.join("progress.jsonl")

    def rows = path.exist? ? path.readlines.filter_map { JSON.parse(it) rescue nil } : []

    def summary
      file = dir.join("eval-history.jsonl")
      line = file.exist? && file.readlines.reverse.find { it.strip.present? }
      line ? JSON.parse(line) : nil
    end

    def model_meta = dir.join("model/hole.json").exist? ? JSON.parse(dir.join("model/hole.json").read) : nil

    # The live sessions (the model ran in them), from the latest summary.
    def live_sessions = (summary&.dig("per_session") || []).select { it["model_n"].to_i.positive? }

    def record!
      s, meta = summary, model_meta
      return unless s && meta
      return if rows.any? { it["version"] == meta["version"] }

      row = row_for(s, meta)
      File.open(path, "a") { it.puts(JSON.generate(row)) }
      row
    end

    def readiness
      live = live_sessions
      h2h = live_totals(live)
      if live.size < MIN_LIVE_SESSIONS
        return Readiness.new(:early, "Too early to tell",
                             "#{live.size} of #{MIN_LIVE_SESSIONS} sessions with the model running live so far. " \
                             "Judge it on live sessions only: they are shots it had never seen.")
      end

      ahead = h2h["model_right"] > h2h["rules_right"] && h2h["model_agree"] >= h2h["rules_agree"]
      detail = "Over #{live.size} live sessions: rings #{h2h["rules_agree"]} (engine) vs #{h2h["model_agree"]} (model) " \
               "of #{h2h["n"]}; where they differed, model right #{h2h["model_right"]}, engine right #{h2h["rules_right"]}."
      if ahead
        Readiness.new(:ahead, "The model is ahead", "#{detail} Worth considering letting it score.")
      else
        Readiness.new(:behind, "Not ahead yet", "#{detail} Keep training on new sessions.")
      end
    end

    def live_totals(live = live_sessions)
      %w[n rules_agree model_agree model_right rules_right neither flagged model_flagged].index_with { 0 }.tap do |t|
        live.each do |s|
          t["n"] += s["model_n"].to_i
          t["rules_agree"] += s["agree"].to_i
          t["model_agree"] += s["model_agree"].to_i
          %w[model_right rules_right neither flagged model_flagged].each { t[it] += s[it].to_i }
        end
      end
    end

    def table
      list = rows
      return "No trained model recorded yet: run bin/rails ml:update after a session." if list.empty?

      fmt = "%-10s %-14s %10s  %-19s %-19s %-19s %-13s %-12s %s"
      head = format(fmt, "date", "model", "trained", "latest (live)", "all live", "held out", "differ: m/e", "median mm", "flags m/e")
      lines = list.map do |r|
        latest, live, held = r["latest_session"] || {}, r["live"] || {}, r["held_out"] || {}
        format(fmt, r["at"].to_s[0, 10], r["version"], "#{r["trained_on"]}/#{r["sessions"]}s",
               pair(latest["rules_agree"], latest["model_agree"], latest["model_n"]),
               pair(live["rules_agree"], live["model_agree"], live["n"]),
               pair(held["rules_agree"], held["model_agree"], held["n"]),
               live["n"].to_i.positive? ? "#{live["model_right"].to_i}/#{live["rules_right"].to_i}" : "-",
               mm(held["rules_median_mm"], held["model_median_mm"]),
               held["model_flagged"] ? "#{held["model_flagged"]}/#{held["rules_flagged"] || "?"}" : "-")
      end
      r = readiness
      ([ head, "-" * head.size ] + lines + [
        "", "#{r.headline.upcase}: #{r.detail}", "",
        "Pairs are engine -> model: rings matching your calls. trained = shots/sessions learned from.",
        "live = estimates made during the session, before the model saw it; held out = shots kept back in training.",
        "differ: m/e = where the two gave different rings, how often the model / the engine was right (live).",
        "median mm = distance from your taps (held out); flags = shots marked uncertain, model/engine.",
        "More, with links to the shots: the Scoring model page in the app."
      ]).join("\n")
    end

    private
      def row_for(summary, meta)
        sessions = summary["per_session"] || []
        latest = sessions.max_by { [ it["date"].to_s, it["session_id"] ] } || {}
        cv = meta["cv"] || {}
        position = cv["position"] || {}
        {
          "at" => Time.current.iso8601, "version" => meta["version"], "trained_on" => meta["trained_on"],
          "sessions" => meta["sessions"], "kinds" => meta["kinds"], "training" => meta["training"],
          "latest_session" => latest.slice("session_id", "date", "n", "model_n", "median_mm", "model_median_mm",
                                           "model_right", "rules_right", "flagged", "model_flagged")
                                    .merge("rules_agree" => latest["agree"],
                                           "model_agree" => (latest["model_agree"] if latest["model_n"].to_i.positive?)),
          "live" => live_totals(sessions.select { it["model_n"].to_i.positive? })
                      .merge("sessions" => sessions.count { it["model_n"].to_i.positive? }),
          "held_out" => {
            "by" => cv["by"], "folds" => cv["folds"], "n" => cv["n"],
            "rules_agree" => cv["rules_agree"], "model_agree" => cv["model_agree"],
            "rules_ci95" => cv["rules_ci95"], "model_ci95" => cv["model_ci95"],
            "rules_median_mm" => cv["rules_median_mm"], "model_median_mm" => cv["model_median_mm"],
            "rules_p90_mm" => position.dig("rules", "p90_mm"), "model_p90_mm" => position.dig("model", "p90_mm"),
            "rules_wrong_spot" => position.dig("rules", "wrong_spot"), "model_wrong_spot" => position.dig("model", "wrong_spot"),
            "model_radial_bias_mm" => position.dig("model", "radial_bias_median_mm"),
            "model_flagged" => cv.dig("model_flags", "flagged"), "model_flags_caught" => cv.dig("model_flags", "caught"),
            "model_wrong" => cv.dig("model_flags", "wrong"),
            "rules_flagged" => cv.dig("flags", "flagged"),   # the same held-out shots as the model's
            "rules_flags_caught" => cv.dig("flags", "caught"), "rules_wrong" => cv.dig("flags", "ring_changed"),
            "head_to_head" => cv["head_to_head"]&.except("shots"), "calibration" => cv["calibration"]
          }
        }
      end

      def pair(rules, model, n)
        return "-" unless n.to_i.positive?

        "#{rules || "?"} -> #{model || "?"} of #{n}"
      end

      def mm(rules, model) = rules && model ? format("%.2f -> %.2f", rules, model) : "-"
  end
end
