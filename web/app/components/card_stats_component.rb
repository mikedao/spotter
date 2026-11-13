# A card's numbers as a grid of labelled figures (CardStats).
class CardStatsComponent < ApplicationComponent
  def initialize(stats:, title: "This card") = (@stats, @title = stats, title)

  def call
    render(CardComponent.new(title: @title)) do
      tag.dl(class: "grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-3") do
        safe_join(figures.map { |label, value| figure(label, value) })
      end
    end
  end

  private
    def figures
      s = @stats
      [
        [ "Total", s.any? ? s.score : "–" ],
        [ "Shots", s.count ],
        [ "Average", s.score_average || "–" ],
        [ "Inner tens", s.inner_tens ],
        [ "Group", s.group_size_mm ? "#{s.group_size_mm} mm" : "–" ],
        [ "Group center", s.count >= 2 ? "#{s.mean_point_offset_mm} mm #{s.mean_point_direction}" : "–" ],
        [ "Mean radius", s.mean_radius_mm ? "#{s.mean_radius_mm} mm" : "–" ],
        [ "Time per shot", s.average_interval_s ? "#{s.average_interval_s} s" : "–" ],
        [ "Found", s.found_by_text || "–" ],
        [ "Sound to score", s.median_detect_s ? "#{s.median_detect_s} s" : "–" ]
      ]
    end

    def figure(label, value)
      tag.div do
        safe_join([
          tag.dt(label, class: "text-sm text-gray-600 dark:text-gray-300"),
          tag.dd(value.to_s, class: "text-lg font-semibold tabular-nums")
        ])
      end
    end
end
