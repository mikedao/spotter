# One of the shooter's guns. Each is ONE type, pistol or rifle (a TargetSpec
# key), so a session only offers guns that match its target. A gun is retired,
# never deleted: old sessions keep pointing at it, and it stops being offered.
class Gun < ApplicationRecord
  include Retirable
  belongs_to :user
  has_many :practice_sessions, dependent: :restrict_with_error

  normalizes :name, :make_model, with: ->(s) { s.squish }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :make_model, length: { maximum: 80 }
  validates :kind, inclusion: { in: TargetSpec::SPECS.keys, message: "must be a pistol or a rifle" }
  validate :kind_kept_once_used

  scope :active, -> { where(retired_at: nil) }
  scope :of_kind, ->(kind) { where(kind:) }
  scope :by_name, -> { order(Arel.sql("lower(guns.name)")) }

  def retired? = retired_at.present?
  def kind_name = TargetSpec::SPECS.fetch(kind).name.delete_prefix("10m ")   # "Air Pistol"
  def label = make_model.present? ? "#{name} (#{make_model})" : name

  private
    # Its sessions were shot at that target; a rifle can't become a pistol after.
    def kind_kept_once_used
      return unless persisted? && kind_changed? && practice_sessions.exists?

      errors.add(:kind, "can't change: this gun has sessions")
    end
end
