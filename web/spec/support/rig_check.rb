# RigCheck keeps each user's last check in the process; start every example clean.
RSpec.configure { it.before { RigCheck.reset! } }
