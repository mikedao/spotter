# A session as Shotmetrix QR codes (ShotmetrixCode), for the shooter to scan into
# the Shotmetrix app. Every scored shot in firing order, sighters flagged; scored
# as the session is (pistol whole rings, rifle and finals decimals); each shot's
# FINAL position and value (your call wins). Over 120 shots: several codes.
#
# Each code's id is fixed per session and part, so scanning a session twice
# doesn't import it twice (Shotmetrix accepts an id once).
#
#   ShotmetrixExport.new(session).urls   # => [ "https://shotmetrix.com/api/qrcode/…" ]
class ShotmetrixExport
  class Nothing < StandardError; end

  def initialize(session)
    @session = session
  end

  def discipline = ShotmetrixCode::FOR_TARGET.fetch(@session.target)
  def decimal? = @session.target == "rifle" || @session.course.to_s.start_with?("final", "ranking")

  def shots = @shots ||= @session.shots.select(&:scored?).sort_by(&:fired_at)
  def parts = shots.each_slice(ShotmetrixCode::MAX_SHOTS).to_a

  def urls
    raise Nothing, "no scored shots in this session" if shots.none? { !it.sighter? }

    parts.each_with_index.map { |part, i| url_for(part, i) }
  end

  private
    def url_for(part, index)
      entries = part.map { entry(it) }
      ShotmetrixCode.url(discipline:, decimal: decimal?, time: @session.started_at, shots: entries, id: id_for(index))
    rescue ShotmetrixCode::Invalid => e
      # A called ring further from its position than Shotmetrix allows: send the
      # value its position gives, so the code is still accepted.
      n = e.message[/\Ashot (\d+): value does not match the position\z/, 1]&.to_i
      raise unless n && !entries[n - 1][:fixed]

      @fixed = (@fixed || {}).merge(part[n - 1].id => true)
      retry
    end

    def entry(shot)
      at = [ shot.fired_at, @session.started_at ].max   # never before the session start
      return { value: 0, sighter: shot.sighter?, time: at } if shot.penalized?   # 0 has no position to match

      x, y = shot.final_x_mm&.to_f, shot.final_y_mm&.to_f
      value = decimal? ? shot.final_decimal.to_f : shot.final_ring.to_i
      if @fixed&.key?(shot.id) && x
        tenths = ShotmetrixCode.value_from_position(x, y, discipline == 1 ? 0.25 : 0.8)
        value = decimal? ? tenths / 10.0 : tenths / 10
      end
      { x:, y:, value:, sighter: shot.sighter?, time: at, fixed: @fixed&.key?(shot.id) }.compact
    end

    # Fixed per session and part (Shotmetrix accepts an id once), not guessable.
    def id_for(index) = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "shotmetrix:#{@session.id}:#{index}")[0, 16]
end
