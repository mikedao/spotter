FactoryBot.define do
  factory :user do
    sequence(:name) { "Shooter #{it}" }
    sequence(:email_address) { "shooter#{it}@example.com" }
    password { "range-day-10" }
  end
end
