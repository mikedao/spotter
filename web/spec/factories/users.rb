FactoryBot.define do
  factory :user do
    sequence(:name) { "Shooter #{it}" }
    sequence(:username) { "shooter#{it}" }
    sequence(:email_address) { "shooter#{it}@example.com" }
    pin { "1010" }
  end
end
