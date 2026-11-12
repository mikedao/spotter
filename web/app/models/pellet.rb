# A pellet the shooter uses - one row per LOT (the tin's lot number), since lots
# of the same pellet shoot differently and match shooters test and buy by lot.
# Added on the Gear page or straight from the session wizard, and remembered for
# reuse; "new lot" copies one and asks only for the lot. Retired, never deleted.
class Pellet < ApplicationRecord
  include Retirable
  belongs_to :user
  has_many :practice_sessions, dependent: :restrict_with_error

  normalizes :name, :lot, with: ->(s) { s.squish }

  validates :name, presence: true, length: { maximum: 80 }
  validates :lot, length: { maximum: 40 }
  validates :weight_grains, numericality: { greater_than: 0, less_than: 50 }, allow_nil: true
  validates :head_mm, numericality: { greater_than_or_equal_to: 4.0, less_than_or_equal_to: 5.0 }, allow_nil: true
  validates :lot, uniqueness: { scope: %i[ user_id name head_mm ], case_sensitive: false,
                                message: "is already in your list for this pellet" }

  scope :active, -> { where(retired_at: nil) }
  scope :by_name, -> { order(Arel.sql("lower(pellets.name)"), :head_mm, :lot) }

  def retired? = retired_at.present?

  # "RWS R10 Match · 4.49 mm · 7.0 gr · lot 1234"
  def label
    [ name, (head_mm && "#{head_mm.to_s('F')} mm"), (weight_grains && "#{weight_grains.round(2).to_s('F')} gr"),
      (lot.present? ? "lot #{lot}" : nil) ].compact.join(" · ")
  end

  # A new tin of the same pellet: everything but the lot.
  def new_lot = user.pellets.new(name:, weight_grains:, head_mm:)
end
