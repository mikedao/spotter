# The range screen's header line: the session, what the engine is doing right now
# (in the same words it says in the shooter's earbuds), and Stop while it runs.
class SessionStatusComponent < ApplicationComponent
  LOOK = {
    "starting" => [ "Starting the engine… (camera and microphone)", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ],
    "ready" => [ "Ready – fire when you like", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "shooting" => [ "Ready for the next shot", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "card_off" => [ "Card off – put up the next card", "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200" ],
    "new_card" => [ "New card – ready", "bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-200" ],
    "paused" => [ "Scoring paused – change the card, then Resume", "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200" ],
    "resuming" => [ "Resuming – finding the card…", "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200" ],
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
      tag.div(class: "flex flex-wrap items-center gap-x-4 gap-y-2 short:gap-x-2 max-sm:gap-x-2") do
        safe_join([
          # a phone upright, live: the title goes (it is in the tab; screen readers keep
          # it) so the status sits beside the menu and the target comes up a row
          tag.h1(@session.title, class: classes("text-2xl font-semibold short:text-lg",
                                                @session.live? ? "max-sm:sr-only" : "max-sm:w-full max-sm:truncate max-sm:text-lg"),
                 title: @session.title),
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

    # Stop; "Pause scoring" to change cards without false shots (Resume while
    # paused); and "Re-find target" for when the camera got bumped: the rings move
    # to where the card is now (the engine takes a new baseline, then "ready").
    def stop_button
      paused = @session.status == "paused"
      tag.div(class: "ml-auto flex flex-wrap items-center gap-2") do
        safe_join([
          (pause_button(paused) if !@session.status.in?(%w[ starting resuming ]) && EngineRunner.understands_pause?(@session)),
          (unless paused || @session.status == "resuming"
             render(ButtonComponent.new(href: refind_practice_session_path(@session), method: :post, variant: :secondary,
                                        title: "Bumped the camera? Find the card again and move the rings to it",
                                        form: { data: { turbo_submits_with: "Re-finding…" } })) { safe_join([ "⌖", tag.span(" Re-find", class: "max-sm:sr-only") ]) }
           end),
          render(ButtonComponent.new(href: stop_practice_session_path(@session), method: :post, variant: :danger,
                                     title: "End the session (a last check for an unscored hole first)")) { "■ Stop" }
        ].compact)
      end
    end

    # Only for an engine that says it can pause (one started before Pause existed
    # would be SUSPENDED by the signal, so it gets no button).
    def pause_button(paused)
      if paused
        render(ButtonComponent.new(href: resume_scoring_practice_session_path(@session), method: :post,
                                   title: "The card is up: find it (same card or new) and score again",
                                   form: { data: { turbo_submits_with: "Resuming…" } })) { safe_join([ "▶", tag.span(" Resume", class: "max-sm:sr-only") ]) }
      else
        render(ButtonComponent.new(href: pause_scoring_practice_session_path(@session), method: :post, variant: :secondary,
                                   title: "Changing cards? Nothing is scored until you resume",
                                   form: { data: { turbo_submits_with: "Pausing…" } })) { safe_join([ "⏸", tag.span(" Pause", class: "max-sm:sr-only") ]) }
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
