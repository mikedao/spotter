# The app's confirmation modal, in place of the browser's confirm() box. Rendered
# once in the layout; confirm_dialog_controller.js makes it Turbo's confirm
# method, so every `data: { turbo_confirm: "..." }` uses it unchanged.
#
# The confirm button reads "Delete" (red, Cancel focused) on a DELETE form and
# "Continue" otherwise; `data: { confirm_button: "Start match" }` on the form or
# button names it.
class ConfirmDialogComponent < ApplicationComponent
end
