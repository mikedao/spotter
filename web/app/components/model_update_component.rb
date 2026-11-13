# The finished session page's "Scoring model" card: once every shot has a call,
# one button runs the after-session routine (ModelUpdate: export, compare,
# retrain) and the card follows it live, then shows how the engine and the model
# did against this session's calls. Hidden for a live session and the demo.
class ModelUpdateComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def render? = !session.live? && session.user.username != TrainingExport::DEMO_USER

  private
    attr_reader :session

    def state = @state ||= ModelUpdate.for_session(session)
    def ready? = ModelUpdate.ready?(session)
    def left = @left ||= ModelUpdate.left_to_review(session)
    def first_unreviewed
      Shot.joins(:card).where(cards: { practice_session_id: session.id }, status: "scored", called_at: nil)
          .order("cards.number", :fired_at, :id).first
    end

    def busy_elsewhere
      return @busy if defined?(@busy)

      other = ModelUpdate.running
      @busy = other && other.id != session.id ? other : nil
    end

    def live_session? = EngineRunner.running.present?

    def this_session = state.result["session"]
    def overall = state.result["overall"]
    def trained = state.result["trained"]

    def of(agree, n) = "#{agree} of #{n}"

    def button(label, variant: :primary)
      render(ButtonComponent.new(href: helpers.update_model_practice_session_path(session), method: :post,
                                 variant:, size: :sm)) { label }
    end
end
