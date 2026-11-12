require "rails_helper"

RSpec.describe Course do
  it "offers exactly the engine's courses (engine/course.py)" do
    out, status = Open3.capture2(EngineRunner.python, "-c",
                                 "import json, course; print(json.dumps({k: [c['name'], c['shots'], c['series']] for k, c in course.COURSES.items()}))",
                                 chdir: EngineRunner.engine_dir.to_s)
    skip "engine Python not available" unless status.success?
    engine = JSON.parse(out)
    expect(described_class::ALL.transform_values { [ it.name, it.shots, it.series_size ] }).to eq engine
  end

  it "scores a pistol match in whole rings, finals and rifle in decimals" do
    expect(described_class.find("match").whole_rings?("pistol")).to be true
    expect(described_class.find("match").whole_rings?("rifle")).to be false
    expect(described_class.find("final").whole_rings?("pistol")).to be false
  end
end

RSpec.describe EventStats do
  let(:session) { create(:practice_session, course: "match") }
  let(:card) { create(:card, practice_session: session) }

  def shot(stage, ring:, decimal:, number: nil, series: nil, penalty: nil)
    create(:shot, card:, stage:, ring:, decimal_score: decimal, match_number: number, series:, penalty:)
  end

  it "counts match shots only, out-of-time shots as zero, a pistol match in whole rings" do
    shot("sighter", ring: 6, decimal: 6.2)
    shot("match", ring: 9, decimal: 9.6, number: 1, series: 1)
    shot("match", ring: 10, decimal: 10.4, number: 2, series: 1)
    shot("match", ring: 8, decimal: 8.9, number: 11, series: 2, penalty: "out of time")

    stats = described_class.new(session.reload)
    expect(stats).to have_attributes(fired: 3, sighters: 1, penalties: 1, total: 19)
    expect(stats.series).to eq [ [ 1, 19 ], [ 2, 0 ] ]
  end

  it "adds decimals in a final" do
    session.update!(course: "final")
    shot("match", ring: 9, decimal: 9.6, number: 1, series: 1)
    shot("match", ring: 10, decimal: 10.4, number: 2, series: 1)
    expect(described_class.new(session.reload).total).to eq 20.0
  end
end
