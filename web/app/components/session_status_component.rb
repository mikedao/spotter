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

  PARTS = %i[ status controls error ].freeze
  # Every session button the same width on a wide screen: a label change (Pause ->
  # Resume) never nudges its neighbours. Disabled ones keep their short label (the
  # pill says "Resuming" / "Stopping"), so nothing outgrows its slot.
  SLOT = "wide:min-w-28".freeze

  # The header comes in three parts, each its own broadcast target (LiveBroadcast):
  # :status (title + pill, left), :controls (Pause / Re-find / Stop, or Continue /
  # Delete, in the toolbar on the right, beside the Mic / Chatty / Sound buttons
  # that live outside every broadcast) and :error (under the header).
  def initialize(session:, part: :status)
    @session = session
    @part = PARTS.include?(part) ? part : raise(ArgumentError, "part: #{part}")
  end

  def self.confirm_delete(session)
    shots = session.cards.sum { it.shots.size }   # uses preloaded shots on the list
    "Delete #{session.title}#{" and its #{shots == 1 ? 'shot' : "#{shots} shots"}" if shots.positive?}? " \
      "Your calls and the pictures go too. This can't be undone."
  end

  # Pushed live by LiveBroadcast, so Stop goes away the moment the session ends and
  # a crash shows up on an open screen. Every part always renders its wrapper, so a
  # later replace has something to land on.
  #
  # The layout must NOT move as the session runs (2026-11-19, the shooter on the
  # iPad: the buttons were staggered over two rows and jumped about): the pill's
  # text changes width with every status, so it sits on the left and truncates;
  # every toolbar button keeps its slot - disabled, not removed, when it can't be
  # used - with a minimum width, so Pause <-> Resume doesn't nudge its neighbours.
  def call
    case @part
    when :status then status
    when :controls then tag.div(id: "session_controls", class: "contents") { @session.live? ? live_controls : finished_controls }
    when :error then tag.div(id: "session_error", class: "mt-3 empty:mt-0") { error_box if @session.engine_error.present? }
    end
  end

  private
    def status
      text, colours = LOOK.fetch(@session.status, LOOK["starting"])
      # Title over the pill until the screen is wide enough for both on one line;
      # either truncates (full text on hover) rather than push the toolbar - the
      # title first: mid-session the status matters more.
      tag.div(id: "session_status", class: "flex min-w-0 items-center gap-x-3 gap-y-1 wide:flex-col wide:items-start xl:flex-row! xl:items-center!") do
        safe_join([
          # a phone upright, live: the title goes (it is in the tab; screen readers keep
          # it) so the status sits beside the menu and the target comes up a row
          tag.h1(@session.title, class: classes("min-w-0 max-w-full truncate font-semibold short:text-lg",
                                                @session.live? ? "text-xl max-sm:sr-only" : "text-2xl max-sm:text-lg"),
                 title: @session.title),
          tag.div(class: classes("flex min-w-0 max-w-full shrink-0 items-center gap-2 rounded-full px-3 py-1 text-sm font-medium", colours),
                  title: text) do
            safe_join([
              (tag.span(class: "inline-block size-2 shrink-0 animate-pulse rounded-full bg-current") if @session.live?),
              tag.span(text, class: "truncate")
            ].compact)
          end
        ].compact)
      end
    end

    # Pause (Resume while paused) to change cards without false shots; Re-find for
    # when the camera got bumped (the engine takes a new baseline, then "ready");
    # Stop. Each is always there while live, disabled when it can't be used now.
    def live_controls
      status = @session.status
      safe_join([
        (pause_button(status) if EngineRunner.understands_pause?(@session)),
        if status.in?(%w[ paused resuming starting stopping ])
          disabled_button("⌖", " Re-find", class: SLOT)
        else
          render(ButtonComponent.new(href: refind_practice_session_path(@session), method: :post, variant: :secondary, class: SLOT,
                                     title: "Bumped the camera? Find the card again and move the rings to it",
                                     form: { data: { turbo_submits_with: "⌖ Finding…" } })) { label("⌖", " Re-find") }
        end,
        if status == "stopping"
          disabled_button("■", " Stop", variant: :danger, class: SLOT)
        else
          render(ButtonComponent.new(href: stop_practice_session_path(@session), method: :post, variant: :danger, class: SLOT,
                                     title: "End the session (a last check for an unscored hole first)")) { "■ Stop" }
        end
      ].compact)
    end

    # Only for an engine that says it can pause (one started before Pause existed
    # would be SUSPENDED by the signal, so it gets no button at all - for the whole
    # session, so the toolbar still never changes shape).
    def pause_button(status)
      width = SLOT
      case status
      when "paused"
        render(ButtonComponent.new(href: resume_scoring_practice_session_path(@session), method: :post, class: width,
                                   title: "The card is up: find it (same card or new) and score again",
                                   form: { data: { turbo_submits_with: "Resuming…" } })) { label("▶", " Resume") }
      when "resuming" then disabled_button("▶", " Resume", class: width)   # the pill says "Resuming"
      when "starting", "stopping" then disabled_button("⏸", " Pause", class: width)
      else
        render(ButtonComponent.new(href: pause_scoring_practice_session_path(@session), method: :post, variant: :secondary, class: width,
                                   title: "Changing cards? Nothing is scored until you resume",
                                   form: { data: { turbo_submits_with: "Pausing…" } })) { label("⏸", " Pause") }
      end
    end

    def label(icon, text) = safe_join([ icon, tag.span(text, class: "max-sm:sr-only") ])

    def disabled_button(icon, text, variant: :secondary, **html)
      render(ButtonComponent.new(variant:, disabled: true, **html)) { label(icon, text) }
    end

    # A finished session: Continue (practice, today - same rig, the engine works
    # out the card) and Delete.
    def finished_controls
      safe_join([
        (render(ButtonComponent.new(href: resume_practice_session_path(@session), method: :post,
                                    title: "Carry on shooting in this session, with the same camera, mic and gear",
                                    form: { data: { turbo_submits_with: "Starting…" } })) { "▶ Continue session" } if @session.continuable?),
        render(ButtonComponent.new(href: practice_session_path(@session), method: :delete, variant: :secondary,
                                   form: { data: { turbo_confirm: self.class.confirm_delete(@session) } })) { "Delete session" }
      ].compact)
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
