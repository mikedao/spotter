# A labelled text input with its errors, the one field style for the app's forms.
#
#   <%= render(TextFieldComponent.new(form: f, field: :name, label: "Name")) %>
class TextFieldComponent < ApplicationComponent
  INPUT = "block w-full rounded-md border border-gray-300 bg-white px-3 py-2 focus:outline-2 focus:outline-blue-600 " \
          "dark:border-gray-700 dark:bg-gray-900".freeze

  def initialize(form:, field:, label:, type: :text_field, hint: nil, **html)
    @form, @field, @label, @type, @hint, @html = form, field, label, type, hint, html
  end

  def call
    errors = @form.object&.errors&.full_messages_for(@field) || []
    tag.div(class: "space-y-1") do
      safe_join([
        @form.label(@field, @label, class: "block text-sm font-medium"),
        @form.public_send(@type, @field, class: INPUT, **@html),
        (tag.p(@hint, class: "text-sm text-gray-600 dark:text-gray-300") if @hint),
        *errors.map { tag.p(it, class: "text-sm text-red-700 dark:text-red-300") }
      ].compact)
    end
  end
end
