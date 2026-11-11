# The app sends no email, so a forgotten password is reset by whoever runs it.
namespace :users do
  desc "Reset a user's password: bin/rails users:reset_password EMAIL=... PASSWORD=..."
  task reset_password: :environment do
    user = User.find_by!(email_address: ENV.fetch("EMAIL").strip.downcase)
    user.update!(password: ENV.fetch("PASSWORD"))
    user.sessions.destroy_all
    puts "Password reset for #{user.name} <#{user.email_address}>; they are signed out everywhere."
  end
end
