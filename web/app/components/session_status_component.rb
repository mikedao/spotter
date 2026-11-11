# The range screen's status line: what the engine is doing right now, in the same
# words it says in the shooter's earbuds.
class SessionStatusComponent < ApplicationComponent
  LOOK = {
    "starting" => [ "Starting…", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ],
    "ready" => [ "Ready – fire when you like", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "shooting" => [ "Ready for the next shot", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "card_off" => [ "Card off – put up the next card", "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200" ],
    "new_card" => [ "New card – ready", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "ended" => [ "Session ended", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ]
  }.freeze

  def initialize(session:) = @session = session

  def call
    text, colours = LOOK.fetch(@session.status, LOOK["starting"])
    tag.div(id: "session_status", class: classes("flex items-center gap-2 rounded-md px-4 py-3 font-medium", colours)) do
      safe_join([
        (tag.span(class: "inline-block size-2.5 animate-pulse rounded-full bg-current") if @session.live?),
        tag.span(text)
      ].compact)
    end
  end
end
