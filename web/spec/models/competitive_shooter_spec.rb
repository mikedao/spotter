require "rails_helper"

RSpec.describe CompetitiveShooter do
  let(:key) { "csk_#{'a' * 32}" }
  let(:sent) { [] }

  # Net::HTTP.start yields a connection; this one keeps the request and answers `response`.
  def answer(code, body)
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s).new("1.1", code.to_s, "")
    allow(response).to receive(:body).and_return(body.to_json)
    http = double("http")
    allow(http).to receive(:request) { |req| sent << req; response }
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  it "posts the pictures as multipart files on the member's key, via Spotter" do
    answer(201, { id: "abc", url: "https://competitiveshooter.org/posts/abc" })
    result = described_class.new(key).post!(body: "Good day", topics: [ "international-issf-pistol" ], images: [ [ "a.jpg", "\xFF\xD8jpeg".b ] ])
    expect(result["url"]).to eq("https://competitiveshooter.org/posts/abc")

    req = sent.first
    expect(req.path).to eq("/api/v1/posts")
    expect(req["Authorization"]).to eq("Bearer #{key}")
    expect(req.content_type).to eq("multipart/form-data")
    body = req.body_stream ? req.body_stream.read : req.body
    body = req.instance_variable_get(:@body_data).inspect if body.nil?
    expect(body).to include("Spotter", "Good day", "topics[]", "images[]", "a.jpg")
  end

  it "says what went wrong, in words" do
    { 401 => /API key/, 403 => /terms/, 429 => /10 posts an hour/ }.each do |code, message|
      answer(code, { errors: [ "x" ] })
      expect { described_class.new(key).post!(body: "", topics: [], images: []) }.to raise_error(CompetitiveShooter::Error, message)
    end
    answer(422, { errors: [ "Images can't be more than 4" ] })
    expect { described_class.new(key).post!(body: "", topics: [], images: []) }.to raise_error(CompetitiveShooter::Error, /more than 4/)
  end

  it "needs a key" do
    expect { described_class.new(nil) }.to raise_error(CompetitiveShooter::Error, /Settings/)
  end

  it "reports a network failure as an error, not a crash" do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError)
    expect { described_class.new(key).post!(body: "", topics: [], images: []) }.to raise_error(CompetitiveShooter::Error, /reach/)
  end
end
