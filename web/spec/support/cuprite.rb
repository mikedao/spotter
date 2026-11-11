# Browser specs (spec/system) run in headless Chrome through Cuprite, as in
# fl-shooters. They need Chrome on the machine.
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1280, 1000 ], headless: true, process_timeout: 20)
end

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }
end
