# The range screen's header line: the session, what the engine is doing right now
# (in the same words it says in the shooter's earbuds), and Stop while it runs.
class SessionStatusComponent < ApplicationComponent
  LOOK = {
    "starting" => [ "Starting the engine… (camera and microphone)", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ],
    "ready" => [ "Ready – fire when you like", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "shooting" => [ "Ready for the next shot", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "card_off" => [ "Card off – put up the next card", "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200" ],
    "new_card" => [ "New card – ready", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "stopping" => [ "Stopping – a last check for an unscored hole…", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ],
    "ended" => [ "Session ended", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ]
  }.freeze

  def initialize(session:) = @session = session

  def self.confirm_delete(session)
    shots = session.cards.sum { it.shots.size }   # uses preloaded shots on the list
    "Delete #{session.title}#{" and its #{shots == 1 ? 'shot' : "#{shots} shots"}" if shots.positive?}? " \
      "Your calls and the pictures go too. This can't be undone."
  end

  # The range screen's header: title, what the engine is doing (a pill), and Stop
  # while it runs - plus the engine's last words when it died. Pushed live by
  # LiveBroadcast, so Stop goes away the moment the session ends and a crash shows
  # up on an open screen.
  def call
    tag.div(id: "session_status", class: "space-y-3") do
      safe_join([ header, (error_box if @session.engine_error.present?) ].compact)
    end
  end

  private
    def header
      text, colours = LOOK.fetch(@session.status, LOOK["starting"])
      tag.div(class: "flex flex-wrap items-center gap-x-4 gap-y-2") do
        safe_join([
          tag.h1(@session.title, class: "text-2xl font-semibold"),
          tag.div(class: classes("flex items-center gap-2 rounded-full px-3 py-1 text-sm font-medium", colours)) do
            safe_join([
              (tag.span(class: "inline-block size-2 animate-pulse rounded-full bg-current") if @session.live?),
              tag.span(text)
            ].compact)
          end,
          (@session.live? ? (stop_button unless @session.status == "stopping") : delete_button)
        ].compact)
      end
    end

    # Stop, and "Re-find target" for when the camera got bumped: the rings move
    # to where the card is now (the engine takes a new baseline, then "ready").
    def stop_button
      tag.div(class: "ml-auto flex flex-wrap items-center gap-2") do
        safe_join([
          render(ButtonComponent.new(href: refind_practice_session_path(@session), method: :post, variant: :secondary,
                                     title: "Bumped the camera? Find the card again and move the rings to it",
                                     form: { data: { turbo_submits_with: "Re-finding…" } })) { "⌖ Re-find target" },
          render(ButtonComponent.new(href: stop_practice_session_path(@session), method: :post, variant: :danger)) { "Stop session" }
        ])
      end
    end

    # A finished session: Continue (practice, today - same rig, the engine works
    # out the card) and Delete.
    def delete_button
      tag.div(class: "ml-auto flex flex-wrap items-center gap-2") do
        safe_join([
          (render(ButtonComponent.new(href: resume_practice_session_path(@session), method: :post,
                                      title: "Carry on shooting in this session, with the same camera, mic and gear",
                                      form: { data: { turbo_submits_with: "Starting…" } })) { "▶ Continue session" } if @session.continuable?),
          render(ButtonComponent.new(href: practice_session_path(@session), method: :delete, variant: :secondary,
                                     form: { data: { turbo_confirm: self.class.confirm_delete(@session) } })) { "Delete session" }
        ].compact)
      end
    end

    def error_box
      tag.div(class: "rounded-md border border-red-300 bg-red-50 p-4 dark:border-red-800 dark:bg-red-950") do
        safe_join([
          tag.p("The engine stopped unexpectedly. The last lines it printed:", class: "mb-2 font-medium text-red-900 dark:text-red-200"),
          tag.pre(@session.engine_error, class: "overflow-x-auto text-sm text-red-900 dark:text-red-200")
        ])
      end
    end
end
