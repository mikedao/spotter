# Adding and editing pellets (one per lot). "New lot" (new?from=ID) copies a
# pellet's name, weight and head size, so only the new tin's lot is typed.
class PelletsController < ApplicationController
  before_action :set_pellet, only: %i[ edit update ]

  def new
    from = Current.user.pellets.find_by(id: params[:from])
    @pellet = from ? from.new_lot : Current.user.pellets.new
  end

  def create
    @pellet = Current.user.pellets.new(pellet_params)
    if @pellet.save
      redirect_to gear_path(anchor: "pellets"), notice: "Added #{@pellet.label}."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @pellet.update(pellet_params)
      redirect_to gear_path(anchor: "pellets"), notice: "Saved #{@pellet.label}."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_pellet
      @pellet = Current.user.pellets.find(params[:id])
    end

    def pellet_params
      params.expect(pellet: [ :name, :weight_grains, :head_mm, :lot, :notes, :retired ])
    end
end
