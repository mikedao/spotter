require "rails_helper"

# What the session's Gun / Pellets pickers offer and pre-select.
RSpec.describe GearChoice do
  let(:user) { create(:user) }
  let(:choice) { described_class.new(user:, target: "pistol") }

  it "offers only active guns of the target's type" do
    lp10 = create(:gun, user:, name: "LP10")
    create(:gun, user:, name: "Old", retired_at: 1.day.ago)
    create(:gun, user:, name: "LG400", kind: "rifle")
    create(:gun, name: "Someone else's")
    expect(choice.guns).to eq([ lp10 ])
  end

  it "pre-selects nothing with nothing to pick, and the only gun and pellets when there is one" do
    expect(choice.gun).to be_nil
    expect(choice.pellet).to be_nil

    gun = create(:gun, user:)
    pellet = create(:pellet, user:)
    choice = described_class.new(user:, target: "pistol")
    expect(choice.gun).to eq(gun)
    expect(choice.pellet).to eq(pellet)
  end

  it "pre-selects the last gun at this target and the pellets last used with it" do
    lp10, morini = create(:gun, user:, name: "LP10"), create(:gun, user:, name: "Morini")
    r10, h_n = create(:pellet, user:), create(:pellet, user:, name: "H&N Finale Match")
    create(:practice_session, user:, gun: lp10, pellet: r10, started_at: 3.days.ago)
    create(:practice_session, user:, gun: morini, pellet: h_n, started_at: 2.days.ago)
    create(:practice_session, user:, started_at: 1.day.ago)   # nothing noted

    expect(choice.gun).to eq(morini)
    expect(choice.pellet).to eq(h_n)
    expect(choice.pellet_by_gun).to eq(lp10.id => r10.id, morini.id => h_n.id)
  end

  it "skips retired gear when pre-selecting, but keeps a session's own" do
    lp10 = create(:gun, user:)
    r10 = create(:pellet, user:)
    session = create(:practice_session, user:, gun: lp10, pellet: r10)
    lp10.update!(retired: "1")
    r10.update!(retired: "1")

    expect(described_class.new(user:, target: "pistol").gun).to be_nil
    editing = described_class.new(user:, target: "pistol", session:)
    expect(editing.guns).to eq([ lp10 ])
    expect(editing.pellet).to eq(r10)
  end
end
