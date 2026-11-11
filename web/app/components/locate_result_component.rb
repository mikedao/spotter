# The camera check's result: the camera's view with the fitted rings over it, and
# each measurement as a plain verdict with what to do about it.
class LocateResultComponent < ApplicationComponent
  ICON = { good: "✓", warn: "!", bad: "✗", info: "·" }.freeze
  COLOUR = {
    good: "text-green-700 dark:text-green-300", warn: "text-amber-700 dark:text-amber-300",
    bad: "text-red-700 dark:text-red-300", info: "text-gray-600 dark:text-gray-300"
  }.freeze

  def initialize(check:, live: false) = (@check, @live = check, live)
end
