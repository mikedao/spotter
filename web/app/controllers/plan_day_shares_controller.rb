# A training-plan day as a post to CompetitiveShooter.org (PlanDayShare): the
# COMPOSER that opens when the day is ticked done and its note saved (the shooter,
# 2026-11-21: never posted by itself). Pick up to four pictures, the colors, name
# and gear, the day card's headline / note / progress, the caption and topics; the
# previews are the very JPEGs that go out. Nothing is posted without Post.
class PlanDaySharesController < ApplicationController
  before_action :load_share

  def show
    @kinds = @share.available_kinds
    @pictures = params.key?(:pictures) ? Array(params[:pictures]).map(&:to_s) & @kinds.keys : @share.picture_kinds
    @body = params.key?(:body) ? params[:body].to_s : @share.body
    @topics = params.key?(:topics) ? Array(params[:topics]).map(&:to_s) & CompetitiveShooter::TOPICS.keys : @share.topics
  end

  def picture
    kind = params[:kind].to_s
    return head :not_found unless @share.available_kinds.key?(kind)

    picture = @share.picture(kind, look: @look)
    expires_now
    send_data picture.jpeg, type: "image/jpeg", disposition: "inline", filename: picture.filename
  rescue SharePicture::RenderError => e
    render plain: e.message, status: :internal_server_error
  end

  def create
    kinds = Array(params[:pictures]).map(&:to_s)
    body = params[:body].to_s.strip.first(CompetitiveShooter::BODY_MAX)
    topics = (Array(params[:topics]).map(&:to_s) & CompetitiveShooter::TOPICS.keys).first(CompetitiveShooter::MAX_TOPICS)
    @share.post!(kinds:, body:, topics:, look: @look)
    @share.workout&.update!(share_error: nil)
    redirect_to plan_workout_path(@share.day.week, @share.day.day), notice: "Posted to CompetitiveShooter.org.", status: :see_other
  rescue CompetitiveShooter::Error, SharePicture::RenderError, PlanDayShare::Invalid => e
    redirect_to plan_day_share_path(@share.day.week, @share.day.day, pictures: kinds, body:, topics:, **@look.to_params),
                alert: e.message, status: :see_other
  end

  private
    def load_share
      @share = PlanDayShare.new(Current.user, params[:week], params[:day])
      # A ticked box sends both its hidden 0 and its 1: the last one counts.
      look = %i[ colors identity headline show_note show_progress ].to_h { [ it, Array(params[it]).last ] }.compact
      @look = PlanDayShare::Look.from(look, Current.user)
    rescue PlanDayShare::Invalid => e
      redirect_to training_plan_path, alert: e.message
    end
end
