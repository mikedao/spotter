# Gear is retired, never deleted (old sessions keep pointing at it). Forms send
# `retired: "1"` / `"0"`; this turns it into retired_at.
module Retirable
  extend ActiveSupport::Concern

  def retired=(value)
    self.retired_at = ActiveModel::Type::Boolean.new.cast(value) ? (retired_at || Time.current) : nil
  end
end
