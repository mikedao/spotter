# A training-plan day as a post to CompetitiveShooter.org (PlanDayShare): the
# preview - the very caption and JPEGs that go out - and "Post it" for a day not
# posted yet (or whose automatic post failed). Ticking a day done posts it by
# itself (PlanDayPostJob).
class PlanDaySharesController < ApplicationController
  before_action :load_share

  def show
    @colors = ShareColorway.key_for(Current.user.share_colors)
  end

  def picture
    kind = params[:kind].to_s
    return head :not_found unless @share.picture_kinds.include?(kind)

    picture = @share.picture(kind)
    expires_now
    send_data picture.jpeg, type: "image/jpeg", disposition: "inline", filename: picture.filename
  rescue SharePicture::RenderError => e
    render plain: e.message, status: :internal_server_error
  end

  def create
    @share.post!
    @share.workout&.update!(share_error: nil)
    redirect_to plan_workout_path(@share.day.week, @share.day.day), notice: "Posted to CompetitiveShooter.org.", status: :see_other
  rescue CompetitiveShooter::Error, SharePicture::RenderError => e
    redirect_to plan_day_share_path(@share.day.week, @share.day.day), alert: e.message, status: :see_other
  end

  private
    def load_share
      @share = PlanDayShare.new(Current.user, params[:week], params[:day])
    rescue PlanDayShare::Invalid => e
      redirect_to training_plan_path, alert: e.message
    end
end
