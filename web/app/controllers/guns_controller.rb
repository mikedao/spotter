# Adding and editing guns, and each gun's page: its sessions with the pellets
# and the gun adjustments noted in each - the gun's history. Opened from the
# session wizard ("Add a gun"), a new gun goes back there (return_to=setup).
class GunsController < ApplicationController
  before_action :set_gun, only: %i[ show edit update ]

  def new
    @gun = Current.user.guns.new(kind: params[:kind].presence_in(TargetSpec::SPECS.keys) || "pistol")
  end

  def create
    @gun = Current.user.guns.new(gun_params)
    if @gun.save
      redirect_to(return_to || gear_path, notice: "Added #{@gun.name}.")
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @sessions = @gun.practice_sessions.newest_first.includes(:pellet, cards: :shots)
  end

  def edit
  end

  def update
    if @gun.update(gun_params)
      redirect_to gun_path(@gun), notice: "Saved #{@gun.name}."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_gun
      @gun = Current.user.guns.find(params[:id])
    end

    def gun_params
      params.expect(gun: [ :name, :kind, :make_model, :notes, :retired ])
    end

    # Only the wizard, never a URL from the request: no open redirect.
    def return_to = (setup_start_path if params[:return_to] == "setup")
    helper_method :return_to
end
