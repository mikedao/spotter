# The live range screen's announcer (announcer_controller.js): the Chatty button
# (commentary on or off at will - users.chatty), the Sound on/off button -
# browsers play sound only after a tap - and the hidden spot Turbo appends each
# announcement to (Announcement). Outside everything LiveBroadcast
# replaces, so it keeps playing through every shot.
class AnnouncerComponent < ApplicationComponent
  def initialize(session:) = @session = session

  def render? = @session.live?

  BUTTON = "cursor-pointer whitespace-nowrap rounded-md border border-gray-300 px-3.5 py-2.5 text-sm font-medium " \
           "pointer-coarse:min-h-11 hover:bg-gray-50 " \
           "aria-pressed:border-green-600 aria-pressed:bg-green-50 aria-pressed:text-green-900 " \
           "dark:border-gray-700 dark:hover:bg-gray-800 dark:aria-pressed:bg-green-950 dark:aria-pressed:text-green-200".freeze

  def call
    tag.div(class: "flex flex-wrap items-center gap-2",
            data: { controller: "announcer", announcer_chatty_value: @session.user.chatty?,
                    announcer_chatty_url_value: helpers.chatty_setting_path }) do
      safe_join([
        tag.button(type: "button", class: BUTTON, data: { announcer_target: "chatty", action: "announcer#toggleChatty" }),
        tag.button(type: "button", class: BUTTON, data: { announcer_target: "button", action: "announcer#toggle" }),
        tag.div(id: "announcements", hidden: true)
      ])
    end
  end
end
