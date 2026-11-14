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
      sound_check["trigger_db"].to_f == SoundTrigger::DB && sound_check["trigger_ms"].to_f == SoundTrigger::MS
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
