require "rails_helper"

RSpec.describe "Accounts" do
  it "says it works with an iPhone, and who is responsible if you shoot it" do
    get new_registration_path
    expect(response.body).to include("Continuity Camera", "out of the line of fire", "isn't responsible if you shoot your camera")
  end

  it "signs up and is signed straight in" do
    post registration_path, params: { user: { name: "Mike", email_address: " Mike@Example.com ",
                                               password: "range-day-10", password_confirmation: "range-day-10" } }
    expect(response).to redirect_to(root_path)
    expect(User.last).to have_attributes(name: "Mike", email_address: "mike@example.com")

    follow_redirect!
    expect(response.body).to include("Mike", "Sign out")
  end

  it "rejects a short password and a taken email" do
    create(:user, email_address: "taken@example.com")
    post registration_path, params: { user: { name: "X", email_address: "taken@example.com", password: "short", password_confirmation: "short" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("has already been taken", "too short")
  end

  it "signs in and out" do
    user = create(:user)
    sign_in(user)
    expect(response).to redirect_to(root_url)

    delete session_path
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "refuses a wrong password" do
    user = create(:user)
    post session_path, params: { email_address: user.email_address, password: "nope" }
    expect(response).to redirect_to(new_session_path)
  end
end
