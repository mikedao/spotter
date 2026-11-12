# A session as Shotmetrix QR codes, to scan into the Shotmetrix app.
class ShotmetrixController < ApplicationController
  def show
    @session = Current.user.practice_sessions.includes(cards: :shots).find(params[:practice_session_id])
    @export = ShotmetrixExport.new(@session)
    @urls = @export.urls
  rescue ShotmetrixExport::Nothing, ShotmetrixCode::Invalid => e
    @error = e.message
  end
end
