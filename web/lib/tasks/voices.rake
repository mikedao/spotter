# Chatty mode's pieces, kept in git like the engine's (public/voice-pieces):
# the list is written here, the audio rendered by the engine's speak.py.
#
#   bin/rails voices:chatty_list                     # after editing config/commentary/*.yml
#   ../engine/voice/.venv/bin/python ../engine/voice/speak.py export --chatty --voice af_bella
namespace :voices do
  desc "Write public/voice-pieces/chatty.txt: every piece chatty mode can say (default goal)"
  task chatty_list: :environment do
    pieces = Commentary.pieces(User.new)   # an unsaved user: the default goals (565 for pistol)
    path = Voice.exported_dir.join("chatty.txt")
    path.write(pieces.join("\n") + "\n")
    puts "#{pieces.size} pieces -> #{path.relative_path_from(Rails.root)}"
  end
end
