# The range screen's status line: what the engine is doing right now, in the same
# words it says in the shooter's earbuds.
class SessionStatusComponent < ApplicationComponent
  LOOK = {
    "starting" => [ "Starting the engine… (camera and microphone)", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ],
    "ready" => [ "Ready – fire when you like", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "shooting" => [ "Ready for the next shot", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "card_off" => [ "Card off – put up the next card", "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200" ],
    "new_card" => [ "New card – ready", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "ended" => [ "Session ended", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ]
  }.freeze

  def initialize(session:) = @session = session

  # Includes the engine's last words when it died, so a crash shows up live on an
  # open range screen (this component is what LiveBroadcast pushes first).
  def call
    text, colours = LOOK.fetch(@session.status, LOOK["starting"])
    tag.div(id: "session_status", class: "space-y-3") do
      safe_join([
        tag.div(class: classes("flex items-center gap-2 rounded-md px-4 py-3 font-medium", colours)) do
          safe_join([
            (tag.span(class: "inline-block size-2.5 animate-pulse rounded-full bg-current") if @session.live?),
            tag.span(text)
          ].compact)
        end,
        (error_box if @session.engine_error.present?)
      ].compact)
    end
  end

  private
    def error_box
      tag.div(class: "rounded-md border border-red-300 bg-red-50 p-4 dark:border-red-800 dark:bg-red-950") do
        safe_join([
          tag.p("The engine stopped unexpectedly. The last lines it printed:", class: "mb-2 font-medium text-red-900 dark:text-red-200"),
          tag.pre(@session.engine_error, class: "overflow-x-auto text-sm text-red-900 dark:text-red-200")
        ])
      end
    end
end
