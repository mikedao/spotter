# Every capture on a card, newest first: scored shots with their score, direction
# and flags, and captures the engine could not score (kept so none is lost). Each
# row opens the shot's review page.
class ShotListComponent < ApplicationComponent
  # deletable: a Delete button on each row (the card page), back to that page after.
  def initialize(shots:, title: "Shots", deletable: false) = (@shots, @title, @deletable = shots, title, deletable)

  def call
    render(CardComponent.new(title: @title)) do
      if @shots.empty?
        tag.p("None yet.", class: "text-gray-600 dark:text-gray-300")
      else
        tag.ul(class: "-mx-4 -mb-4 divide-y divide-gray-200 sm:-mx-5 sm:-mb-5 dark:divide-gray-800") do
          safe_join(@shots.reverse.map { row(it) })
        end
      end
    end
  end

  private
    def row(shot)
      tag.li(class: "flex items-center") do
        safe_join([
          link_to(shot_path(shot), class: "flex min-w-0 flex-1 flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800") do
            shot.scored? ? scored_row(shot) : unscored_row(shot)
          end,
          (delete_button(shot) if @deletable)
        ].compact)
      end
    end

    def delete_button(shot)
      what = shot.scored? ? "shot #{shot.number}" : "this unscored capture"
      tag.div(class: "shrink-0 px-2") do
        button_to("Delete", shot_path(shot, back: "card"), method: :delete, "aria-label": "Delete #{what}",
                  form: { data: { turbo_confirm: "Delete #{what}? Its pictures and your call go too, and the later shots on this card move up a number. This can't be undone." } },
                  class: "min-h-11 cursor-pointer rounded-md px-3 text-sm text-gray-500 hover:bg-red-50 hover:text-red-700 dark:text-gray-400 dark:hover:bg-red-950 dark:hover:text-red-300")
      end
    end

    def scored_row(shot)
      safe_join([
        tag.span(shot.sighter? ? "S" : "##{shot.match_number || shot.number}", class: "w-8 text-gray-600 dark:text-gray-300",
                 title: (shot.sighter? ? "sighter" : nil)),
        tag.span(format("%.1f", shot.final_decimal),
                 class: classes("w-12 text-lg font-semibold tabular-nums", ("text-gray-500 line-through" if shot.penalized?))),
        tag.span(shot.direction, class: "w-24"),
        tag.span(shot.trigger == "sound" ? "heard" : "seen", class: "text-sm text-gray-600 dark:text-gray-300"),
        badges(shot)
      ])
    end

    def unscored_row(shot)
      safe_join([
        tag.span("–", class: "w-8 text-gray-600 dark:text-gray-300"),
        tag.span("Not scored", class: "font-medium text-amber-700 dark:text-amber-300"),
        tag.span(shot.unscored_reason, class: "text-sm text-gray-600 dark:text-gray-300")
      ])
    end

    def badges(shot)
      list = []
      list << badge("sighter", "bg-gray-100 text-gray-800 dark:bg-gray-800 dark:text-gray-200") if shot.sighter?
      list << badge("#{shot.penalty} - scores 0", "bg-red-100 text-red-900 dark:bg-red-950 dark:text-red-200") if shot.penalized?
      list << badge("called #{shot.call_ring}", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200") if shot.called?
      shot.flags.each { list << badge(it, "bg-red-100 text-red-900 dark:bg-red-950 dark:text-red-200") } unless shot.called?
      tag.span(safe_join(list, " "), class: "ml-auto flex flex-wrap gap-1")
    end

    def badge(text, colours) = tag.span(text, class: classes("rounded px-2 py-0.5 text-sm", colours))
end
