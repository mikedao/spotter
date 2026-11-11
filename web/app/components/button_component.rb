# Copied from fl-shooters (app/components); keep the two in step.
# One button style for the whole app. Renders as:
#   - a <button> (default, use inside forms)
#   - an <a> when `href:` is given
#   - a one-off form via button_to when `href:` and `method:` are given
#
#   <%= render(ButtonComponent.new(href: new_event_path, variant: :primary)) { "New event" } %>
#   <%= render(ButtonComponent.new(href: session_path, method: :delete, variant: :ghost)) { "Log out" } %>
#   <%= render(ButtonComponent.new(type: :submit)) { "Save" } %>
class ButtonComponent < ApplicationComponent
  VARIANTS = {
    primary: "bg-blue-600 text-white hover:bg-blue-500",
    secondary: "border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 text-gray-800 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800",
    danger: "bg-red-600 text-white hover:bg-red-500",
    ghost: "text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100",
    # For the header bar: quiet on_brand buttons, and one white inverse call to action.
    on_brand: "text-blue-100 hover:bg-white/10 hover:text-white",
    inverse: "bg-white text-brand hover:bg-gray-100"
  }.freeze

  # pointer-coarse: on a touch screen every button reaches the 44 px tap-target floor.
  SIZES = {
    sm: "px-3 py-1.5 text-sm pointer-coarse:min-h-11",
    md: "px-3.5 py-2.5 text-sm pointer-coarse:min-h-11",
    lg: "px-5 py-3 text-base pointer-coarse:min-h-12"
  }.freeze

  def initialize(variant: :primary, size: :md, href: nil, method: nil, type: :button, full_width: false, **html)
    @variant = VARIANTS.fetch(variant)
    @size = SIZES.fetch(size)
    @href = href
    @method = method
    @type = type
    @full_width = full_width
    @html = html
  end

  # Guard against `render Component.new(...) { }` where Ruby binds the block to
  # `new`, leaving the button with no label.
  def before_render
    raise ArgumentError, "ButtonComponent needs a label: use render(ButtonComponent.new(...)) { \"Label\" }" if content.blank?
  end

  def call
    if @href && @method
      button_to(content, @href, method: @method, class: css, **@html)
    elsif @href
      link_to(content, @href, class: css, **@html)
    else
      tag.button(content, type: @type, class: css, **@html)
    end
  end

  private
    def css
      classes(
        "inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-md font-medium cursor-pointer",
        "disabled:cursor-not-allowed disabled:opacity-50",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-current",
        @variant, @size,
        (@full_width ? "w-full" : nil),
        @html.delete(:class)
      )
    end
end
