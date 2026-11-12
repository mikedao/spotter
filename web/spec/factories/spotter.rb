FactoryBot.define do
  factory :practice_session do
    user
    sequence(:engine_session_id) { "20261111-1530#{it.to_s.rjust(2, '0')}-test" }
    target { "pistol" }
    rule { "pellet" }
    status { "ready" }
    started_at { Time.zone.parse("2026-11-11 15:30") }
  end

  factory :card do
    practice_session
    sequence(:number) { it }
    started_at { Time.zone.parse("2026-11-11 15:31") }
  end

  factory :shot do
    card
    sequence(:number) { it }
    status { "scored" }
    trigger { "sound" }
    sequence(:fired_at) { |n| Time.zone.parse("2026-11-11 15:31") + (n * 20).seconds }
    x_mm { 0.0 }
    y_mm { 0.0 }
    r_mm { 0.0 }
    decimal_score { 10.9 }
    ring { 10 }
    rule { "pellet" }
  end
end

FactoryBot.define do
  factory :gun do
    user
    sequence(:name) { "LP#{it}" }
    kind { "pistol" }
  end

  factory :pellet do
    user
    name { "RWS R10 Match" }
    head_mm { 4.49 }
    weight_grains { 7.0 }
    sequence(:lot) { "L#{1000 + it}" }
  end
end
