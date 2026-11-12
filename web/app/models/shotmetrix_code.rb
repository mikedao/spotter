# Shotmetrix QR code, version 1: a session's shots, encrypted for the Shotmetrix
# app to import by scanning (open format, no API key, no registration needed).
# A Ruby port of Shotmetrix's Apache-2.0 reference encoder
# (github.com/shotmetrix/Shotmetrix-QRCode, python/shotmetrix_qrcode.py; format in
# its SPEC.md), checked byte for byte against its published test vectors
# (spec/fixtures/files/shotmetrix/test-vectors.json). "Shotmetrix" is a name of
# Shotmetrix Kemmer GmbH, used here only to say this produces Shotmetrix QR codes.
#
#   ShotmetrixCode.url(discipline: 3, decimal: false, time: started_at,
#                      shots: [ { x: 1.2, y: -0.8, value: 9, sighter: false, time: fired_at }, ... ])
#   # => "https://shotmetrix.com/api/qrcode/AE…"   (1557 Base32 characters: always QR version 24)
#
# Shots: x/y in mm from the centre (x right, y UP), value in rings (decimal or
# whole), optional time. Raises ShotmetrixCode::Invalid (the reference's English
# messages) rather than build a code Shotmetrix would refuse.
class ShotmetrixCode
  class Invalid < ArgumentError; end

  PUBLIC_KEY = "G6bDi6iNtkyrkAsv+upJPQxE9Vj2jY6BEhSX5weZIB8="   # keys/shotmetrix-public-key.txt
  URL_PREFIX = "https://shotmetrix.com/api/qrcode/"
  VERSION = 1
  PLAINTEXT_BYTES = 924
  MAX_SHOTS = 120
  SHOT_BYTES = 7
  INFO = "shotmetrix-qrcode-v1"
  UNITS = [ 0.01, 0.1, 0.2 ].freeze
  NO_POS = 0x800
  NO_TIME = 0xFFFFFF
  EPOCH_2000 = 946_684_800

  # discipline => [ zone widths in mm, allowed value/position difference in tenths ]
  DISCIPLINES = { 1 => [ [ 0.25 ], 3 ], 2 => [ [ 0.25 ], 3 ], 3 => [ [ 0.8 ], 3 ], 4 => [ [ 0.8 ], 3 ], 5 => [ [ 0.8 ], 3 ],
                  6 => [ [ 0.8 ], 3 ], 7 => [ [ 0.8 ], 3 ], 8 => [ [ 2.5, 4.0 ], 10 ], 9 => [ nil, nil ],
                  10 => [ [ 2.5 ], 10 ], 11 => [ [ 2.5 ], 10 ], 12 => [ [ 2.5 ], 10 ] }.freeze
  FOR_TARGET = { "rifle" => 1, "pistol" => 3 }.freeze   # 10 m air rifle / air pistol

  class << self
    def url(public_key: PUBLIC_KEY, **args) = URL_PREFIX + base32(seal(plaintext(**args), public_key))

    # Halves away from zero (Ruby's Float#round already does; kept explicit, as the spec insists).
    def round_half_away(v) = (v.abs + 0.5).floor * (v.negative? ? -1 : 1)

    # The value in tenths that a position gives (SPEC.md, section 7).
    def value_from_position(x, y, zone)
      tenths = 110 - ((Math.sqrt(x * x + y * y) / zone * 1e6 + 0.5).floor / 1e6).ceil
      tenths.clamp(0, 109).then { it < 10 ? 0 : it }
    end

    def base32(data)
      alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
      data.unpack1("B*").scan(/.{1,5}/).map { alphabet[it.ljust(5, "0").to_i(2)] }.join
    end

    def plaintext(discipline:, decimal:, time:, shots:, app: 0, app_secret: nil, id: nil, fill: nil, now: nil)
      fail_with("shots: 1 to 120 shots") unless shots.is_a?(Array) && shots.size.between?(1, MAX_SHOTS)
      fail_with("discipline: unknown number") unless discipline.is_a?(Integer) && DISCIPLINES.key?(discipline)
      zones, tol = DISCIPLINES[discipline]
      now = number?(now) ? now : Time.now.to_f
      start = timestamp(time)&.floor
      fail_with("time: session start must be after 2000-01-01 and not in the future") unless start && start.between?(EPOCH_2000, now + 86_400)
      fail_with("app: 0 to 65535") unless app.is_a?(Integer) && app.between?(0, 65_535)
      fail_with("id: 16 bytes") if id && id.bytesize != 16

      values, times, m, last, scored = [], [], 0.0, -1, 0
      shots.each_with_index do |s, i|
        n = "shot #{i + 1}: "
        fail_with("#{n}value must be a number") unless s.is_a?(Hash) && number?(s[:value])
        v = s[:value]
        fail_with("#{n}value out of range") if v.abs > 1000
        value = decimal ? round_half_away(v * 10) : v.floor * 10
        fail_with("#{n}value out of range") unless decimal ? (value.zero? || value.between?(10, 109)) : value.between?(0, 100)
        x, y = s[:x], s[:y]
        fail_with("#{n}give x and y together") if x.nil? != y.nil?
        unless x.nil?
          fail_with("#{n}position must be a number") unless number?(x) && number?(y)
          fail_with("#{n}position outside ±409.4 mm") if x.abs > 409.4 || y.abs > 409.4
          m = [ m, x.abs, y.abs ].max
        end
        t = NO_TIME
        unless s[:time].nil?
          shot_ts = timestamp(s[:time]) || fail_with("#{n}time must be a number or a date")
          t = round_half_away((shot_ts - start) * 100)
          fail_with("#{n}time before the session start or more than 46 h after it") unless t >= 0 && t < NO_TIME
          fail_with("#{n}time earlier than the shot before") if t < last
          fail_with("#{n}time in the future") if start + t / 100.0 > now + 86_400
          last = t
        end
        scored += 1 unless s[:sighter]
        values << value
        times << t
      end
      fail_with("no scored shot") if scored.zero?
      unit = UNITS.index { m / it <= 2047 }
      mm = UNITS[unit]

      if tol
        limit = decimal ? tol : [ 10, tol ].max
        shots.each_with_index do |s, i|
          next if s[:sighter] || s[:x].nil?

          xq, yq = round_half_away(s[:x] / mm) * mm, round_half_away(s[:y] / mm) * mm
          ok = zones.any? do |zone|
            expected = value_from_position(xq, yq, zone)
            expected = expected / 10 * 10 unless decimal
            (expected - values[i]).abs <= limit
          end
          fail_with("shot #{i + 1}: value does not match the position") unless ok
        end
      end

      total = 0
      body = shots.each_with_index.map do |s, i|
        total += values[i] unless s[:sighter]
        x, y = s[:x].nil? ? [ NO_POS, NO_POS ] : [ round_half_away(s[:x] / mm) & 0xFFF, round_half_away(s[:y] / mm) & 0xFFF ]
        [ (x << 20) | (y << 8) | (values[i] << 1) | (s[:sighter] ? 1 : 0) ].pack("N") + [ times[i] ].pack("N")[1, 3]
      end.join.b
      rest = SHOT_BYTES * (MAX_SHOTS - shots.size)
      body += fill ? fill.byteslice(0, rest) : SecureRandom.random_bytes(rest)
      head = (id || SecureRandom.random_bytes(16)).b + [ app ].pack("n") + ("\0" * 8) + [ start ].pack("N") +
             [ discipline, (decimal ? 1 : 0) | (unit << 1), shots.size ].pack("C3") + [ total ].pack("n") + "\0"
      pt = (head.b + body + ("\0" * 48)).b
      if app.positive? && app_secret
        mac = OpenSSL::HMAC.digest("SHA256", app_secret, pt)[0, 8]   # the app_mark field is still zero here
        pt = pt.byteslice(0, 18) + mac + pt.byteslice(26..)
      end
      raise "plaintext is #{pt.bytesize} bytes" unless pt.bytesize == PLAINTEXT_BYTES

      pt
    end

    def seal(pt, public_key, ephemeral_private: nil)
      server = public_key.is_a?(String) && public_key.bytesize != 32 ? (Base64.strict_decode64(public_key) rescue "") : public_key.to_s.b
      fail_with("publicKey: 32 bytes") unless server.bytesize == 32
      fail_with("ephemeralPrivate: 32 bytes") if ephemeral_private && ephemeral_private.bytesize != 32
      priv = ephemeral_private ? OpenSSL::PKey.new_raw_private_key("X25519", ephemeral_private) : OpenSSL::PKey.generate_key("X25519")
      eph = priv.raw_public_key
      shared = priv.derive(OpenSSL::PKey.new_raw_public_key("X25519", server))
      okm = OpenSSL::KDF.hkdf(shared, salt: eph + server, info: INFO, length: 44, hash: "SHA256")
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = okm.byteslice(0, 32)
      cipher.iv = okm.byteslice(32, 12)
      cipher.auth_data = [ VERSION ].pack("C")
      ct = cipher.update(pt) + cipher.final
      ([ VERSION ].pack("C") + eph + ct + cipher.auth_tag).b
    end

    private
      def fail_with(message) = raise(Invalid, message)
      def number?(v) = (v.is_a?(Integer) || v.is_a?(Float)) && v.to_f.finite?

      def timestamp(t)
        return t.to_f if t.respond_to?(:to_time) && !t.is_a?(Numeric)

        number?(t) ? t.to_f : nil
      end
  end
end
