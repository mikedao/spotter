# The Gun and Pellets pickers plus the gun-adjustments note, inside a session
# form (the wizard's Start step and the session page). Both pickers are optional
# and pre-selected by GearChoice. "New pellets…" opens fields to type them in
# (saved to the list by GearParams); "New lot" copies the chosen pellets so only
# the lot needs typing. Changing the gun picks the pellets last used with it.
#
#   <%= render(GearFieldsComponent.new(form: f, choice: GearChoice.new(user:, target:))) %>
class GearFieldsComponent < ApplicationComponent
  INPUT = TextFieldComponent::INPUT

  def initialize(form:, choice:, target:, adjustments: nil, return_to: nil)
    @form, @choice, @target, @adjustments, @return_to = form, choice, target, adjustments, return_to
  end

  private
    attr_reader :form, :choice

    def kind_name = TargetSpec::SPECS.fetch(@target).name.delete_prefix("10m ").downcase   # "air pistol"

    def gun_options
      [ [ "None", "" ] ] + choice.guns.map { [ it.retired? ? "#{it.label} (retired)" : it.label, it.id ] }
    end

    def pellet_options
      options = choice.pellets.map do |p|
        [ p.retired? ? "#{p.label} (retired)" : p.label, p.id,
          { data: { name: p.name, weight: p.weight_grains&.to_s("F"), head: p.head_mm&.to_s("F") } } ]
      end
      [ [ "None", "" ] ] + options + [ [ "New pellets…", GearParams::NEW ] ]
    end

    def new_gun_path = helpers.new_gun_path(kind: @target, return_to: @return_to)
end
