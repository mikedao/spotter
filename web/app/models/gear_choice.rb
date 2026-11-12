# What a session's Gun and Pellets pickers offer and pre-select (the wizard's
# Start step and the session page). Both are optional; the pre-selection makes
# the usual start one tap:
#   gun:     the last gun used at this target, else the only one of that type
#   pellets: the last pellets used WITH THAT GUN, else the last used at all,
#            else the only ones in the list
# Only active (not retired) gear is offered - plus, on an existing session, what
# it already has, so editing it never silently drops a retired gun.
class GearChoice
  def initialize(user:, target:, session: nil)
    @user, @target, @session = user, target, session
  end

  def guns
    @guns ||= (@user.guns.active.of_kind(@target).by_name.to_a | [ @session&.gun ].compact)
  end

  def pellets
    @pellets ||= (@user.pellets.active.by_name.to_a | [ @session&.pellet ].compact)
  end

  def gun
    return @session.gun if @session

    id = history.find { |gun_id, _| gun_id && guns.any? { it.id == gun_id } }&.first
    guns.find { it.id == id } || (guns.first if guns.one?)
  end

  def pellet
    return @session.pellet if @session

    pellet_for(gun&.id)
  end

  # gun id -> the pellets last used with it, so changing the gun picks its pellets.
  def pellet_by_gun = guns.to_h { [ it.id, pellet_for(it.id)&.id ] }

  private
    # [gun_id, pellet_id] of every earlier session, newest first.
    def history
      @history ||= @user.practice_sessions.where(target: @target).newest_first.pluck(:gun_id, :pellet_id)
    end

    def all_history
      @all_history ||= @user.practice_sessions.newest_first.pluck(:gun_id, :pellet_id)
    end

    def pellet_for(gun_id)
      usable = ->(id) { id && pellets.any? { it.id == id } }
      id = (gun_id && all_history.find { |g, p| g == gun_id && usable.(p) }&.last) ||
           all_history.find { |_, p| usable.(p) }&.last
      pellets.find { it.id == id } || (pellets.first if pellets.one?)
    end
end
