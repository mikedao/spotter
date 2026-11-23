require "rails_helper"

RSpec.describe SpotterHttps do
  around { |ex| original = ENV["SPOTTER_HTTPS_PORT"]; ex.run; ENV["SPOTTER_HTTPS_PORT"] = original }

  it "puts a port other than 443 in the address" do
    ENV["SPOTTER_HTTPS_PORT"] = "3443"
    expect(described_class.url("sussudio.local", "/practice/1")).to eq("https://sussudio.local:3443/practice/1")
  end

  it "leaves 443 out, as a browser shows it" do
    ENV["SPOTTER_HTTPS_PORT"] = "443"
    expect(described_class.url("sussudio.local", "/practice/1")).to eq("https://sussudio.local/practice/1")
  end

  it "defaults to 3443" do
    ENV.delete("SPOTTER_HTTPS_PORT")
    expect(described_class.url("sussudio.local")).to eq("https://sussudio.local:3443/")
  end
end
