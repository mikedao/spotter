# Copied from fl-shooters (app/components); keep the two in step.
# Base class for all components. Keep shared helpers here.
class ApplicationComponent < ViewComponent::Base
  private
    # Joins Tailwind class fragments, dropping nils and blanks.
    def classes(*fragments)
      fragments.flatten.compact_blank.join(" ")
    end
end
