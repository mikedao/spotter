# A post made on CompetitiveShooter.org's feed from Spotter: which sessions it
# showed and where it is, so a session page can link to it.
class SharedPost < ApplicationRecord
  belongs_to :user

  scope :newest_first, -> { order(created_at: :desc) }

  # The posts that showed this session (alone or with others).
  def self.showing(session) = newest_first.select { it.session_ids.include?(session.id) }
end
