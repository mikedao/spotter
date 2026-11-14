# Browser specs (spec/system) run in headless Chrome through Cuprite, as in
# fl-shooters. They need Chrome on the machine.
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1280, 1000 ], headless: true, process_timeout: 20)
end

# With a fake microphone (Chrome's: a beep every half second, 20 ms - too short
# to be a shot) and sound allowed without a tap: the browser trigger and the
# browser's sound check (spec/system/browser_mic_spec.rb). `driven_by :cuprite_mic`.
Capybara.register_driver(:cuprite_mic) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1280, 1000 ], headless: true, process_timeout: 20,
                                browser_options: { "use-fake-ui-for-media-stream" => nil,
                                                   "use-fake-device-for-media-stream" => nil,
                                                   "autoplay-policy" => "no-user-gesture-required" })
end

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }
end
