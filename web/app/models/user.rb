# A shooter. Sign-up is open; each user sees only their own practice sessions.
# There is no password-reset email (this app sends none): whoever runs the
# spotter resets one with `bin/rails users:reset_password EMAIL=... PASSWORD=...`.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :practice_sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true, length: { maximum: 60 }
  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
end
