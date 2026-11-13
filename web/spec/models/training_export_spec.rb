require "rails_helper"

RSpec.describe TrainingExport do
  let(:dir) { Rails.root.join("tmp/training-export-test") }
  let(:user) { create(:user) }
  let(:card) { create(:card, practice_session: create(:practice_session, user:)) }
  let(:closeup) { { "centre" => [ 10.0, -6.0 ], "px_per_mm" => 20.0, "size_px" => 480 } }

  before { FileUtils.rm_rf(dir) }
  after { FileUtils.rm_rf(dir) }

  def shot(**attrs)
    create(:shot, card:, x_mm: 10.0, y_mm: -6.0, ring: 9, decimal_score: 9.4,
                  estimates: { "centroid" => [ 10.0, -6.0 ], "closeup" => closeup }, **attrs).tap do |s|
      s.closeup_before.attach(io: StringIO.new("BEFORE"), filename: "closeup_before.jpg", content_type: "image/jpeg")
      s.closeup_after.attach(io: StringIO.new("AFTER"), filename: "closeup_after.jpg", content_type: "image/jpeg")
    end
  end

  def export(**) = described_class.new(dir:, **).call
  def index = dir.join("index.jsonl").readlines.map { JSON.parse(it) }

  it "exports called shots only, with their close-ups and the proposal and call kept apart" do
    called = shot(call_ring: 8, call_x_mm: 10.5, call_y_mm: -6.2, called_at: Time.current)
    shot # not called yet

    result = export
    expect(result.exported).to eq(1)
    label = index.sole
    expect(label).to include("shot_id" => called.id, "target" => "pistol", "rule" => "pellet", "closeup" => closeup)
    expect(label["proposal"]).to include("x_mm" => 10.0, "ring" => 9, "decimal" => 9.4)
    expect(label["call"]).to include("kind" => "tapped", "ring" => 8, "x_mm" => 10.5)
    folder = dir.join("shots", format("%06d", called.id))
    expect(folder.join("after.jpg").binread).to eq("AFTER")
    expect(folder.join("before.jpg").binread).to eq("BEFORE")
    expect(JSON.parse(folder.join("label.json").read)).to eq(label)
  end

  it "says how each call was made: tapped, accepted as scored, or a ring changed without a tap" do
    tapped = shot(call_ring: 9, call_x_mm: 10.1, call_y_mm: -6.0, called_at: Time.current)
    accepted = shot(call_ring: 9, called_at: Time.current)
    ring_only = shot(call_ring: 8, called_at: Time.current)

    export
    kinds = index.to_h { [ it["shot_id"], it.dig("call", "kind") ] }
    expect(kinds).to eq(tapped.id => "tapped", accepted.id => "accepted", ring_only.id => "ring_only")
  end

  it "mirrors the database: a second run writes no pictures again and removes shots no longer called" do
    keep = shot(call_ring: 9, called_at: Time.current)
    gone = shot(call_ring: 9, called_at: Time.current)
    expect(export.images_written).to eq(4)

    gone.update!(called_at: nil, call_ring: nil)
    result = export
    expect(result).to have_attributes(exported: 1, images_written: 0, removed: 1)
    expect(dir.join("shots").children.map { it.basename.to_s }).to eq([ format("%06d", keep.id) ])
  end

  it "leaves the demo user's replays out unless asked for by login" do
    demo = create(:user, username: "demo")
    create(:card, practice_session: create(:practice_session, user: demo)).then do |demo_card|
      create(:shot, card: demo_card, call_ring: 10, called_at: Time.current)
    end
    shot(call_ring: 9, called_at: Time.current)

    expect(index_users(export)).to eq([ user.username ])
    expect(index_users(export(login: "Demo"))).to eq([ "demo" ])
  end

  def index_users(_result) = index.map { it["user"] }
end
