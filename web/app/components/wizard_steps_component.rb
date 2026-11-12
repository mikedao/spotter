# The new-session wizard's progress: Camera > Camera check > Microphone > Start,
# with the current step marked and earlier ones as links back.
#
#   <%= render(WizardStepsComponent.new(current: :check)) %>
class WizardStepsComponent < ApplicationComponent
  STEPS = { camera: "Camera", check: "Camera check", microphone: "Microphone", start: "Start" }.freeze

  def initialize(current:) = @current = current

  def call
    now = STEPS.keys.index(@current)
    tag.ol(class: "mb-4 flex flex-wrap gap-x-2 gap-y-1 text-sm", "aria-label": "New session steps") do
      safe_join(STEPS.each_with_index.map do |(key, label), i|
        text = "#{i + 1}. #{label}"
        item = if i == now
          tag.span(text, class: "font-semibold text-blue-700 dark:text-blue-300", "aria-current": "step")
        elsif i < now
          link_to(text, helpers.public_send(:"setup_#{key}_path"), class: "text-gray-700 underline dark:text-gray-200")
        else
          tag.span(text, class: "text-gray-500 dark:text-gray-400")
        end
        tag.li(safe_join([ item, (tag.span("›", class: "ml-2 text-gray-400", "aria-hidden": true) if i < STEPS.size - 1) ].compact))
      end)
    end
  end
end
