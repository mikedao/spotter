require "rails_helper"

# What the range screen plays after an engine event: diagnostic sentences only
# in diagnostic mode.
RSpec.describe Announcement do
  let(:user) { create(:user, voice: "bf_emma") }
  let(:session) { create(:practice_session, user:) }

  # The engine's "announce" event for "shot 4. 9.6, shot a touch low. line call".
  let(:shot) do
    { "kind" => "check", "plain_kind" => "ok", "gaps" => { "sentence" => 0.55, "comma" => 0.25 },
      "sentences" => [ { "pieces" => [ "shot 4" ], "diagnostic" => false },
                       { "pieces" => [ "9.6", "shot a touch low" ], "diagnostic" => false },
                       { "pieces" => [ "line call", "found without a sound" ], "diagnostic" => true } ] }
  end

  def texts(announcement) = announcement.payload[:sentences].map { |s| s.map(&:first) }

  it "says only the number, score and direction with diagnostic mode off, with the plain tone" do
    a = described_class.new(session, shot)
    expect(texts(a)).to eq([ [ "shot 4" ], [ "9.6", "shot a touch low" ] ])
    expect(a.payload[:kind]).to eq("ok")
    expect(a.payload[:sentences].first.first.last).to eq("/voices/bf_emma/piece?text=shot+4")
  end

  it "adds why the shot is worth a look with diagnostic mode on" do
    user.update!(diagnostic_announcements: true)
    a = described_class.new(session, shot)
    expect(texts(a).last).to eq([ "line call", "found without a sound" ])
    expect(a.payload[:kind]).to eq("check")
  end

  it "says nothing when everything was diagnostic" do
    geometry = { "kind" => "check", "plain_kind" => nil,
                 "sentences" => [ { "pieces" => [ "geometry warning", "consider a fresh card" ], "diagnostic" => true } ] }
    expect(described_class.new(session, geometry).playable?).to be(false)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    described_class.new(session, geometry).deliver!
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
  end

  it "pushes a playable one to the session's range screens" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    described_class.new(session, shot).deliver!
    expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
      .with(session, target: "announcements", html: a_string_including('data-controller="announcement"'))
  end
end
