# CompetitiveShooter.org's posting API (fl-shooters, docs at /developers): one
# post to the member's feed with up to 4 pictures, on their API key. The post
# shows "via Spotter". 10 posts an hour per member, counted together with the
# site's own form.
#
#   CompetitiveShooter.new(user.cso_api_key).post!(body: "...", topics: [ "international-issf-pistol" ],
#                                                  images: [ [ "hero.jpg", bytes ] ])
#   # => { "id" => "p_...", "url" => "https://competitiveshooter.org/posts/..." }
class CompetitiveShooter
  class Error < StandardError; end

  BASE_URL = ENV.fetch("SPOTTER_CSO_URL", "https://competitiveshooter.org")
  VIA = "Spotter"
  MAX_IMAGES = 4
  MAX_TOPICS = 3
  BODY_MAX = 2000

  # The site's topics as listed on /developers (2026-11-20). An unknown slug is
  # refused by the site, so a topic added there needs adding here.
  TOPICS = {
    "international-issf-pistol" => "International / ISSF Pistol",
    "bullseye-precision-pistol" => "Bullseye / Precision Pistol",
    "gear" => "Gear",
    "other" => "Other"
  }.freeze

  # Air rifle has no topic of its own there.
  def self.default_topics(target) = target == "pistol" ? [ "international-issf-pistol" ] : [ "other" ]

  def initialize(key, base_url: BASE_URL)
    raise Error, "Add your CompetitiveShooter.org API key in Settings first." if key.blank?

    @key = key
    @uri = URI.join(base_url, "/api/v1/posts")
  end

  def post!(body:, topics:, images:)
    fields = [ [ "body", body.to_s ], [ "via", VIA ] ]
    topics.each { fields << [ "topics[]", it ] }
    images.each { |name, bytes| fields << [ "images[]", StringIO.new(bytes), { filename: name, content_type: "image/jpeg" } ] }

    request = Net::HTTP::Post.new(@uri)
    request["Authorization"] = "Bearer #{@key}"
    request["Accept"] = "application/json"
    request.set_form(fields, "multipart/form-data")

    response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == "https", open_timeout: 10, read_timeout: 60) do |http|
      http.request(request)
    end
    handle(response)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    raise Error, "Couldn't reach CompetitiveShooter.org (#{e.class.name.demodulize}). Check the connection and try again."
  end

  private
    def handle(response)
      data = JSON.parse(response.body.to_s) rescue {}
      case response.code.to_i
      when 201 then data
      when 401 then raise Error, "CompetitiveShooter.org didn't accept your API key - it may have been revoked. Check it in Settings."
      when 403 then raise Error, "CompetitiveShooter.org won't take posts from your account right now: confirm your email, or agree to their updated terms on the site."
      when 429 then raise Error, "That's CompetitiveShooter.org's limit of 10 posts an hour. Try again later."
      else raise Error, "CompetitiveShooter.org refused the post: #{Array(data['errors']).join(', ').presence || "HTTP #{response.code}"}"
      end
    end
end
