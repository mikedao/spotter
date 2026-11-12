# Open sign-up: anyone who can reach the app can make an account.
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: [ :name, :username, :email_address, :pin, :pin_confirmation ]))
    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome, #{@user.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end
end
