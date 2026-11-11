# Copied from fl-shooters (app/components); keep the two in step.
# The one card surface: white on light, gray-900 on dark (a step up from the
# gray-950 page), matching FormSectionComponent. Optional header with a
# title and an action on the right.
#
#   <%= render(CardComponent.new(tag: :article, id: dom_id(post))) { ... } %>
#   <%= render(CardComponent.new(title: "Coming up")) do |card| %>
#     <% card.with_action { link_to "All events", events_path } %>
#     ...
#   <% end %>
class CardComponent < ApplicationComponent
  SURFACE = "rounded-lg border border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900".freeze
  PADDING = { none: nil, md: "p-4 sm:p-5" }.freeze

  renders_one :action

  def initialize(tag: :section, title: nil, padding: :md, **html)
    @tag = tag
    @title = title
    @padding = PADDING.fetch(padding)
    @html = html
  end

  def call
    heading_id = "#{@html[:id] || @title.to_s.parameterize}-heading" if @title
    content_tag(@tag, **@html.except(:class), class: classes(SURFACE, @padding, @html[:class]), "aria-labelledby": heading_id) do
      safe_join([ (header(heading_id) if @title), content ].compact)
    end
  end

  private
    def header(heading_id)
      tag.div(class: "mb-3 flex items-baseline justify-between gap-3") do
        safe_join([ tag.h2(@title, id: heading_id, class: "font-semibold"), action ].compact)
      end
    end
end
