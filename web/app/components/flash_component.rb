# The flash messages as toasts (flash_controller.js): floating over the top of
# the page, so they take no room and nothing below moves. A notice ("Saved the
# diary") fades away after 5 s - not while the pointer is on it; an alert (an
# error) stays until closed, since it may still need reading. Each has a close
# button; screen readers hear a notice politely, an alert at once.
class FlashComponent < ApplicationComponent
  LOOK = {
    "alert" => "border-red-300 bg-red-50 text-red-900 dark:border-red-800 dark:bg-red-950 dark:text-red-100",
    "notice" => "border-green-300 bg-green-50 text-green-900 dark:border-green-800 dark:bg-green-950 dark:text-green-100"
  }.freeze

  def initialize(flash:) = @flash = flash

  def render? = @flash.any?

  def call
    tag.div(class: "pointer-events-none fixed inset-x-0 top-3 z-50 flex flex-col items-center gap-2 px-4",
            aria: { live: "polite" }) do
      safe_join(@flash.map { |kind, message| toast(kind.to_s, message) })
    end
  end

  private
    def toast(kind, message)
      alert = kind == "alert"
      tag.div(role: (alert ? "alert" : "status"),
              class: classes("pointer-events-auto flex w-full max-w-md items-start gap-3 rounded-lg border px-4 py-3 shadow-lg",
                             "transition-all duration-300", LOOK.fetch(kind, LOOK["notice"])),
              data: { controller: "flash", flash_dismiss_after_value: (alert ? 0 : 5000),
                      action: "mouseenter->flash#pause mouseleave->flash#resume" }) do
        safe_join([
          tag.p(message, class: "min-w-0 flex-1"),
          tag.button("✕", type: "button", "aria-label": "Close", data: { action: "flash#close" },
                     class: "-my-1 -mr-2 grid size-8 shrink-0 cursor-pointer place-items-center rounded-md opacity-70 hover:opacity-100")
        ])
      end
    end
end
