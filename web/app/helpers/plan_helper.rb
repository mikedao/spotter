# Small pieces the training plan screens share.
module PlanHelper
  KIND_LABELS = { "air" => "Air pistol", "dry" => "Dry fire + lane", "rest" => "Rest" }.freeze
  KIND_STYLES = {
    "air" => "bg-blue-100 text-blue-900 dark:bg-blue-950 dark:text-blue-200",
    "dry" => "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200",
    "rest" => "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300"
  }.freeze

  def plan_kind_badge(day)
    tag.span(KIND_LABELS.fetch(day.kind), class: "rounded px-2 py-0.5 text-sm #{KIND_STYLES.fetch(day.kind)}")
  end

  # "about 60 min", or nothing for a day with no set time.
  def plan_minutes(day) = (day.minutes.positive? ? "about #{day.minutes} min" : nil)

  def plan_date(date) = date.strftime("%a %b %-d")
end
