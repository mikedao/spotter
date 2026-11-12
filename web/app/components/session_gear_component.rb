# The session page's "Gun and pellets" card: what was shot and what was changed
# on the gun, editable during the session or after (forgot to pick, wrong lot).
# Outside everything LiveBroadcast replaces, so a shot never resets a half-typed
# note.
class SessionGearComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def call
    render(CardComponent.new(title: "Gun and pellets", id: "gear")) do
      form_with model: @session, url: helpers.practice_session_path(@session), method: :patch, class: "space-y-4" do |f|
        safe_join([
          render(GearFieldsComponent.new(form: f, choice: GearChoice.new(user: @session.user, target: @session.target, session: @session),
                                         target: @session.target, adjustments: @session.gun_adjustments)),
          tag.div(render(ButtonComponent.new(type: :submit, variant: :secondary)) { "Save" })
        ])
      end
    end
  end
end
