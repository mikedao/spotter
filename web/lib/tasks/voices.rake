# Chatty mode's pieces, kept in git like the engine's (public/voice-pieces):
# the list is written here, the audio rendered by the engine's speak.py.
#
#   bin/rails voices:chatty_list                     # after editing config/commentary/*.yml
#   ../engine/voice/.venv/bin/python ../engine/voice/speak.py export --chatty --voice af_bella
#   bin/rails voices:personality_list ID=katey             # after editing a personality's bank
#   ../engine/voice/.venv/bin/python ../engine/voice/speak.py export --personality katey --voice af_nicole
namespace :voices do
  desc "Write public/voice-pieces/chatty.txt: every piece chatty mode can say (default goal)"
  task chatty_list: :environment do
    pieces = Commentary.pieces(User.new)   # an unsaved user: the default goals (565 for pistol)
    path = Voice.exported_dir.join("chatty.txt")
    path.write(pieces.join("\n") + "\n")
    puts "#{pieces.size} pieces -> #{path.relative_path_from(Rails.root)}"
  end

  desc "Write public/voice-pieces/personality-<id>.txt: every piece a personality's bank can say (ID=katey)"
  task personality_list: :environment do
    id = ENV.fetch("ID", "katey")
    abort "no such personality: #{id}" unless Personality.valid?(id)
    pieces = PersonalityBank.pieces(id)
    path = Voice.exported_dir.join("personality-#{id}.txt")
    path.write(pieces.join("\n") + "\n")
    puts "#{pieces.size} pieces -> #{path.relative_path_from(Rails.root)}"
    puts "render: ../engine/voice/.venv/bin/python ../engine/voice/speak.py export --personality #{id} --voice #{Personality.find(id).voice}"
  end
end
