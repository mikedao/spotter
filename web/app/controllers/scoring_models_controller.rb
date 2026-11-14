# The Scoring model page: how the learned hole locator is coming along
# (ModelProgress) - whether it is ready to score, its numbers over trainings and
# live sessions, and the shots where it and the engine disagreed.
class ScoringModelsController < ApplicationController
  def show
    @rows = ModelProgress.rows
    @summary = ModelProgress.summary
    @meta = ModelProgress.model_meta
    @readiness = ModelProgress.readiness
    @live = ModelProgress.live_sessions
    @sessions = Current.user.practice_sessions.where(id: (@summary&.dig("per_session") || []).map { it["session_id"] }).index_by(&:id)
    # the shots it is about, the user's own only
    ids = (@summary&.dig("head_to_head", "shots") || []).map { it["shot_id"] }
    @own_shots = Shot.joins(card: :practice_session).where(practice_sessions: { user_id: Current.user.id }, id: ids).pluck(:id).to_set
  end
end
