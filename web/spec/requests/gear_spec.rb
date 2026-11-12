require "rails_helper"

# Guns and pellets: the Gear page, and choosing them for a session.
RSpec.describe "Guns and pellets" do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "adds a gun and lists it" do
    get gear_path
    expect(response.body).to include("No guns yet")

    post guns_path, params: { gun: { name: "LP10", kind: "pistol", make_model: "Steyr LP10" } }
    expect(response).to redirect_to(gear_path)
    get gear_path
    expect(response.body).to include("LP10 (Steyr LP10)", "Air Pistol", "0 sessions")
  end

  it "goes back to the session wizard after adding a gun from it, and nowhere else" do
    post guns_path, params: { gun: { name: "LP10", kind: "pistol" }, return_to: "setup" }
    expect(response).to redirect_to(setup_start_path)
    post guns_path, params: { gun: { name: "LP11", kind: "pistol" }, return_to: "https://evil.example" }
    expect(response).to redirect_to(gear_path)
  end

  it "refuses a gun without a name or type" do
    post guns_path, params: { gun: { name: "", kind: "shotgun" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Name can&#39;t be blank", "must be a pistol or a rifle")
  end

  it "retires a gun and can bring it back" do
    gun = create(:gun, user:)
    patch gun_path(gun), params: { gun: { retired: "1" } }
    expect(gun.reload).to be_retired
    patch gun_path(gun), params: { gun: { retired: "0" } }
    expect(gun.reload).not_to be_retired
  end

  it "won't change the type of a gun that has sessions" do
    gun = create(:gun, user:)
    create(:practice_session, user:, gun:)
    patch gun_path(gun), params: { gun: { kind: "rifle" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(gun.reload.kind).to eq("pistol")
  end

  it "shows a gun's sessions with their pellets and adjustments" do
    gun = create(:gun, user:, name: "LP10")
    pellet = create(:pellet, user:, lot: "1234")
    create(:practice_session, user:, gun:, pellet:, gun_adjustments: "Sights 2 clicks right")
    get gun_path(gun)
    expect(response.body).to include("RWS R10 Match · 4.49 mm · 7.0 gr · lot 1234", "Sights 2 clicks right")
  end

  it "keeps another user's gear out of reach" do
    other_gun = create(:gun)
    get gun_path(other_gun)
    expect(response).to have_http_status(:not_found)
    get edit_pellet_path(create(:pellet))
    expect(response).to have_http_status(:not_found)
  end

  it "starts a new lot from existing pellets, asking only for the lot" do
    r10 = create(:pellet, user:, lot: "1234")
    get new_pellet_path(from: r10.id)
    expect(response.body).to include("New lot of RWS R10 Match", 'value="4.49"')

    post pellets_path, params: { pellet: { name: "RWS R10 Match", head_mm: "4.49", weight_grains: "7.0", lot: "5678" } }
    expect(user.pellets.pluck(:lot)).to contain_exactly("1234", "5678")
    post pellets_path, params: { pellet: { name: "RWS R10 Match", head_mm: "4.49", lot: "5678" } }
    expect(response.body).to include("already in your list")
  end

  describe "choosing them for a session" do
    let(:start) { { target: "pistol", per_card: 10, camera: "1", mic: "Razer Kiyo" } }

    before do
      user.update!(last_camera: "1", last_mic: "Razer Kiyo")
      allow(EngineRunner).to receive(:start!) { |**args| create(:practice_session, user:, **args.slice(:target), **args[:gear]) }
    end

    it "pre-selects them on the wizard's Start step" do
      gun = create(:gun, user:, name: "LP10")
      pellet = create(:pellet, user:)
      create(:practice_session, user:, gun:, pellet:)
      get setup_start_path
      expect(response.body).to include("LP10", pellet.label, "Gun adjustments")
      expect(response.body).to match(/<option selected="selected" value="#{gun.id}">LP10/)
    end

    it "offers to add a gun when there is none of that type" do
      create(:gun, user:, kind: "rifle")
      get setup_start_path
      expect(response.body).to include("No air pistol yet")
    end

    it "starts with a gun, typed-in pellets (remembered) and the day's adjustments" do
      gun = create(:gun, user:)
      post practice_sessions_path, params: { practice_session: start.merge(
        gun_id: gun.id, pellet_id: "new", gun_adjustments: "Trigger lighter",
        new_pellet: { name: "H&N Finale Match", head_mm: "4.50", weight_grains: "8.18", lot: "77" }) }

      session = user.practice_sessions.last
      expect(session.gun).to eq(gun)
      expect(session.pellet.label).to eq("H&N Finale Match · 4.5 mm · 8.18 gr · lot 77")
      expect(session.gun_adjustments).to eq("Trigger lighter")
      expect(user.pellets.count).to eq(1)

      # Typed in the same again: the same entry, not a copy.
      post practice_sessions_path, params: { practice_session: start.merge(
        pellet_id: "new", new_pellet: { name: "h&n finale match", head_mm: "4.5", lot: "77" }) }
      expect(user.pellets.count).to eq(1)
    end

    it "starts with none, and with 'New pellets' left empty" do
      post practice_sessions_path, params: { practice_session: start.merge(gun_id: "", pellet_id: "new", new_pellet: { name: "" }) }
      session = user.practice_sessions.last
      expect([ session.gun, session.pellet ]).to eq([ nil, nil ])
      expect(user.pellets).to be_empty
    end

    it "ignores another user's gun" do
      post practice_sessions_path, params: { practice_session: start.merge(gun_id: create(:gun).id) }
      expect(user.practice_sessions.last.gun).to be_nil
    end
  end

  describe "on the session page" do
    let(:session) { create(:practice_session, user:, status: "ended", ended_at: Time.current) }

    it "sets the gun, pellets and adjustments afterwards" do
      gun = create(:gun, user:, name: "LP10")
      pellet = create(:pellet, user:)
      get practice_session_path(session)
      expect(response.body).to include("Gun and pellets")

      patch practice_session_path(session), params: { practice_session: { gun_id: gun.id, pellet_id: pellet.id, gun_adjustments: "Sights up 1" } }
      expect(response).to redirect_to(practice_session_path(session, anchor: "gear"))
      expect(session.reload).to have_attributes(gun:, pellet:, gun_adjustments: "Sights up 1")

      get practice_sessions_path
      expect(response.body).to include("LP10 · RWS R10 Match")
    end

    it "refuses a rifle for a pistol session" do
      rifle = create(:gun, user:, kind: "rifle")
      patch practice_session_path(session), params: { practice_session: { gun_id: rifle.id } }
      follow_redirect!
      expect(response.body).to include("is an air rifle, not for this target")
      expect(session.reload.gun).to be_nil
    end
  end
end
