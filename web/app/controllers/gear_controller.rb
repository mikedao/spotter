# The Gear page: the shooter's guns and pellets, each with how often it was used.
class GearController < ApplicationController
  def show
    @guns = Current.user.guns.by_name.to_a
    @pellets = Current.user.pellets.by_name.to_a
    @uses = Current.user.practice_sessions.group(:gun_id).count
    @pellet_uses = Current.user.practice_sessions.group(:pellet_id).count
  end
end
