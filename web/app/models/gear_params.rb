# Turns the Gun / Pellets pickers' params (GearFieldsComponent) into records of
# the signed-in user's: ids are looked up through the user (another user's id is
# simply not found), and pellet_id "new" creates the pellets typed in beside it -
# which is how they are remembered for next time.
#
#   GearParams.new(user, params[:practice_session]).attributes
#   # => { gun: <Gun>, pellet: <Pellet>, gun_adjustments: "..." }
class GearParams
  NEW = "new".freeze

  def initialize(user, params)
    @user = user
    @params = params || {}
  end

  # Raises ActiveRecord::RecordInvalid for new pellets that don't validate.
  def attributes
    { gun: (@user.guns.find_by(id: @params[:gun_id]) if @params[:gun_id].present?),
      pellet:,
      gun_adjustments: @params[:gun_adjustments].to_s.strip.presence }
  end

  private
    def pellet
      id = @params[:pellet_id].to_s
      return if id.blank?
      return @user.pellets.find_by(id:) unless id == NEW

      fields = @params[:new_pellet] || {}
      return if fields.values_at(:name, :lot, :weight_grains, :head_mm).all?(&:blank?)   # left empty: none

      pellet =@user.pellets.new(name: fields[:name], lot: fields[:lot].presence,
                                 weight_grains: fields[:weight_grains].presence, head_mm: fields[:head_mm].presence)
      same_one(pellet)&.tap { it.update!(retired_at: nil) } || pellet.tap(&:save!)
    end

    # Typed in again (same name, head size and lot): use the one in the list.
    def same_one(pellet)
      @user.pellets.where("lower(name) = ?", pellet.name.to_s.downcase)
           .find_by(head_mm: pellet.head_mm, lot: pellet.lot)
    end
end
