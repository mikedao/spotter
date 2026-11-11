# Request specs sign in through the real login form, so the session cookie is set
# exactly as in the app.
module SignInHelper
  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "range-day-10" }
  end
end

RSpec.configure { it.include SignInHelper, type: :request }
