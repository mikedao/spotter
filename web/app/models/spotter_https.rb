# The https side of bin/dev (config/puma.rb's ssl_bind): the port, and a page's
# address over https - a browser lets only https pages use the microphone. Port 443
# is left out of the address, as a browser shows it.
module SpotterHttps
  def self.port = ENV.fetch("SPOTTER_HTTPS_PORT", "3443").to_s

  def self.url(host, path = "/")
    "https://#{host}#{":#{port}" unless port == "443"}#{path}"
  end
end
