require "rails_helper"

RSpec.describe "Accounts" do
  it "says it works with an iPhone, and who is responsible if you shoot it" do
    get new_registration_path
    expect(response.body).to include("Continuity Camera", "out of the line of fire", "isn't responsible if you shoot your camera")
  end

  it "signs up and is signed straight in" do
    post registration_path, params: { user: { name: "Mike", username: " MikeD ", email_address: " Mike@Example.com ",
                                               pin: "4321", pin_confirmation: "4321" } }
    expect(response).to redirect_to(root_path)
    expect(User.last).to have_attributes(name: "Mike", username: "miked", email_address: "mike@example.com")

    follow_redirect!
    expect(response.body).to include("Mike", "Sign out")
  end

  it "rejects a taken username, a taken email and a PIN that isn't 4-8 digits" do
    create(:user, username: "taken", email_address: "taken@example.com")
    post registration_path, params: { user: { name: "X", username: "Taken", email_address: "taken@example.com", pin: "12a", pin_confirmation: "12a" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Username has already been taken", "Email address has already been taken", "must be 4 to 8 digits")
  end

  it "rejects a username with spaces or symbols" do
    post registration_path, params: { user: { name: "X", username: "mike d!", email_address: "x@example.com", pin: "1234", pin_confirmation: "1234" } }
    expect(response.body).to include("can only use letters, numbers")
  end

  it "signs in and out" do
    user = create(:user)
    sign_in(user)
    expect(response).to redirect_to(root_url)

    delete session_path
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs in with the username in any case" do
    user = create(:user, username: "miked")
    post session_path, params: { username: " MikeD ", pin: "1010" }
    expect(response).to redirect_to(root_url)
  end

  it "refuses a wrong PIN, and the email in place of the username" do
    user = create(:user)
    post session_path, params: { username: user.username, pin: "9999" }
    expect(response).to redirect_to(new_session_path)
    post session_path, params: { username: user.email_address, pin: "1010" }
    expect(response).to redirect_to(new_session_path)
  end
end
