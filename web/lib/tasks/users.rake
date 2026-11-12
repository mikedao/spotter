# The app sends no email, so a forgotten PIN is reset by whoever runs it.
namespace :users do
  desc "Reset a user's PIN: bin/rails users:reset_pin LOGIN=... PIN=..."
  task reset_pin: :environment do
    user = User.find_by!(username: ENV.fetch("LOGIN").strip.downcase)
    user.update!(pin: ENV.fetch("PIN"))
    user.sessions.destroy_all
    puts "PIN reset for #{user.name} (#{user.username}); they are signed out everywhere."
  end
end
