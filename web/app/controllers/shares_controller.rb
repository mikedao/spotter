# Posting sessions to CompetitiveShooter.org: a finished session (its page's Share
# button) or a day of training picked on the journal. The page previews the very
# JPEGs that will be posted (up to four: SharePicture::KINDS), in a colorway,
# with or without the shooter's name and gear; Post sends them with a caption
# and topics through the member's API key. Nothing is posted without Post.
class SharesController < ApplicationController
  before_action :load_set

  def new
  end

  # One picture as it will be posted, for the preview.
  def picture
    kind = params[:kind].to_s
    return head :not_found unless SharePicture.kinds_for(@set).key?(kind)

    picture = SharePicture.build(kind, @set, colors: @colors, identity: @identity)
    expires_now
    send_data picture.jpeg, type: "image/jpeg", disposition: "inline", filename: picture.filename
  rescue SharePicture::RenderError => e
    render plain: e.message, status: :internal_server_error
  end

  def create
    kinds = @pictures
    return fail_with("Pick at least one picture to post.") if kinds.empty?

    images = kinds.map { |k| p = SharePicture.build(k, @set, colors: @colors, identity: @identity); [ p.filename, p.jpeg ] }
    result = CompetitiveShooter.new(Current.user.cso_api_key).post!(body: @body, topics: @topics, images:)
    Current.user.shared_posts.create!(post_id: result["id"].to_s, url: result["url"].to_s, session_ids: @set.ids, pictures: kinds)
    Current.user.update!(share_colors: @colors)
    redirect_to after_post_path, notice: "Posted to CompetitiveShooter.org."
  rescue CompetitiveShooter::Error, SharePicture::RenderError => e
    fail_with(e.message)
  end

  private
    def load_set
      @set = ShareSet.find(Current.user, params[:session_ids])
      @colors = ShareColorway.key_for(params[:colors].presence || Current.user.share_colors)
      @identity = params[:identity] != "0"
      @kinds = SharePicture.kinds_for(@set)
      @pictures = Array(params[:pictures]).map(&:to_s) & @kinds.keys
      @pictures = @kinds.keys if action_name == "new" && params[:pictures].nil?
      @body = params[:body].to_s.strip.first(CompetitiveShooter::BODY_MAX)
      @topics = (Array(params[:topics]).map(&:to_s) & CompetitiveShooter::TOPICS.keys).first(CompetitiveShooter::MAX_TOPICS)
      @topics = CompetitiveShooter.default_topics(@set.spec.key) if action_name == "new" && params[:topics].nil?
      @posted = Current.user.shared_posts.newest_first.select { it.session_ids.sort == @set.ids.sort }
    rescue ShareSet::Invalid => e
      redirect_back_or_to journal_path, alert: e.message
    end

    def fail_with(message)
      flash.now[:alert] = message
      render :new, status: :unprocessable_content
    end

    def after_post_path = @set.single? ? practice_session_path(@set.session, anchor: "export") : journal_path
end
