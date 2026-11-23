# The Colors picker on the share pages (shares/new, the plan day's post composer):
# every ShareColorway, in fl-shooters' Dark / Light / Bold rows. Each theme is a
# round swatch alone (its name is the title and is read out); the checked one grows
# into a pill with its name, so thirty-odd themes fit in a few rows on a phone. Pure
# CSS. `input_data:` carries the page's Stimulus action onto every radio.
class ColorwayPickerComponent < ApplicationComponent
  DOT = "flex items-center gap-2 rounded-full border-2 border-transparent p-0.5 pointer-coarse:min-h-11 pointer-coarse:min-w-11 pointer-coarse:justify-center " \
        "peer-checked:border-blue-600 peer-checked:pr-2 peer-focus-visible:ring-2 peer-focus-visible:ring-blue-600".freeze

  def initialize(checked:, input_data: {})
    @checked = ShareColorway.key_for(checked)
    @input_data = input_data
  end

  # A theme's swatch: its background's two colours, with its accent in the lower corner.
  def self.swatch(theme) = "background: linear-gradient(135deg, #{theme.bg1}, #{theme.bg2} 62%, #{theme.accent} 62%)"

  private
    attr_reader :checked, :input_data
end
