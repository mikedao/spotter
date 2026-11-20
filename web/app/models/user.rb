# A shooter. Sign-up is open; each user sees only their own practice sessions.
# They sign in with a username (case-insensitive) and a 4-8 digit PIN; the email
# address is stored but not used to sign in.
# There is no PIN-reset email (this app sends none): whoever runs the spotter
# resets one with `bin/rails users:reset_pin LOGIN=... PIN=...`.
class User < ApplicationRecord
  has_secure_password :pin
  has_many :sessions, dependent: :destroy
  has_many :practice_sessions, dependent: :destroy
  has_many :guns, dependent: :destroy        # after the sessions that point at them
  has_many :pellets, dependent: :destroy
  has_many :exercises, dependent: :destroy
  has_one :plan_enrollment, dependent: :destroy   # the training plan, once started
  has_many :slow_drills, dependent: :destroy
  has_many :timed_drills, dependent: :destroy
  has_many :hold_drills, dependent: :destroy
  has_many :shared_posts, dependent: :destroy

  # CompetitiveShooter.org API key (`csk_` + 32 base58, made on their profile's API
  # keys page). Stored as typed: this is a one-device SQLite app, and the member can
  # revoke the key there at any time. Never shown back in full (`cso_key_hint`).
  normalizes :cso_api_key, with: ->(k) { k.strip.presence }
  validates :cso_api_key, format: { with: /\Acsk_[1-9A-HJ-NP-Za-km-z]{32}\z/, message: "should look like csk_ followed by 32 letters and digits" }, allow_nil: true
  validates :share_colors, inclusion: { in: ->(_) { ShareColorway.keys } }, allow_nil: true

  def cso_connected? = cso_api_key.present?
  def cso_key_hint = cso_api_key && "csk_…#{cso_api_key.last(4)}"
  def display_name = name.presence || username

  normalizes :username, with: ->(u) { u.strip.downcase }
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.squish }

  # The microphone the last passing sound check used (see the migration):
  # the session wizard won't ask again for it.
  # A sound check counts only for the mic it was made with AND at today's trigger
  # level: one passed at +45 dB said nothing once the trigger rose to +62
  # (2026-11-13: every shot of a session went unheard behind a remembered pass).
  def sound_checked?(mic)
    mic.present? && sound_check.is_a?(Hash) && sound_check["mic"] == mic &&
      sound_check["trigger_db"].to_f == SoundTrigger.level(self, mic) && sound_check["trigger_ms"].to_f == SoundTrigger::MS
  end
  def sound_checked_at = (Time.zone.parse(sound_check["at"].to_s) if sound_check.is_a?(Hash))

  validates :name, presence: true, length: { maximum: 60 }
  validates :username, presence: true, uniqueness: true, length: { in: 3..30 },
                       format: { with: /\A[a-z0-9_.-]+\z/, allow_blank: true,
                                 message: "can only use letters, numbers, _ . and -" }
  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :pin, format: { with: /\A\d{4,8}\z/, message: "must be 4 to 8 digits" }, allow_nil: true
end
