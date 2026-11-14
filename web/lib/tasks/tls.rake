# HTTPS for the range screen on another machine (2026-11-13). A browser lets a
# page use the MICROPHONE only over https (or on localhost), and the range screen
# on the laptop listens for the gun there (the browser trigger). This makes a
# small certificate authority for this one machine and a server certificate for
# its network names; bin/dev then also serves https on SPOTTER_HTTPS_PORT (3443).
#
#   bin/rails spotter:tls        # once; again after an IP change (the CA is kept)
#
# Then trust storage/tls/spotter-ca.pem ONCE on each device that opens the range
# screen (the laptop: double-click it, Keychain Access > "Spotter local CA" >
# Trust > Always Trust), and open https://<this mac>.local:3443.
#
# Everything stays in storage/tls (gitignored): the CA's key never leaves this
# machine, and it can only vouch for names it was given here.
require "openssl"
require "socket"

namespace :spotter do
  desc "Make a local HTTPS certificate so the laptop's browser can use its microphone"
  task :tls do
    dir = Pathname(__dir__).join("../../storage/tls").expand_path
    dir.mkpath
    ca_key_path, ca_path = dir.join("spotter-ca-key.pem"), dir.join("spotter-ca.pem")

    if ca_path.exist? && ca_key_path.exist?
      ca_key = OpenSSL::PKey.read(ca_key_path.read)
      ca = OpenSSL::X509::Certificate.new(ca_path.read)
      puts "Using the existing CA (already trusted devices stay trusted): #{ca_path}"
    else
      ca_key = OpenSSL::PKey::EC.generate("prime256v1")
      ca = OpenSSL::X509::Certificate.new
      ca.version = 2
      ca.serial = OpenSSL::BN.rand(64)
      ca.subject = ca.issuer = OpenSSL::X509::Name.parse("/O=Spotter/CN=Spotter local CA (#{Socket.gethostname})")
      ca.public_key = ca_key
      ca.not_before = Time.now - 60
      ca.not_after = Time.now + (10 * 365 * 86_400)
      ext = OpenSSL::X509::ExtensionFactory.new(ca, ca)
      ca.add_extension(ext.create_extension("basicConstraints", "CA:TRUE,pathlen:0", true))
      ca.add_extension(ext.create_extension("keyUsage", "keyCertSign,cRLSign", true))
      ca.add_extension(ext.create_extension("subjectKeyIdentifier", "hash"))
      ca.sign(ca_key, OpenSSL::Digest.new("SHA256"))
      ca_key_path.write(ca_key.to_pem)
      ca_key_path.chmod(0o600)
      ca_path.write(ca.to_pem)
      puts "Made a new CA: #{ca_path} - trust it on the laptop (see lib/tasks/tls.rake)"
    end

    local = `scutil --get LocalHostName 2>/dev/null`.strip.presence || Socket.gethostname.split(".").first
    names = [ "#{local}.local", "localhost" ]
    ips = [ "127.0.0.1" ] + Socket.ip_address_list.select { it.ipv4? && it.ipv4_private? }.map(&:ip_address)

    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = OpenSSL::BN.rand(64)
    cert.subject = OpenSSL::X509::Name.parse("/O=Spotter/CN=#{names.first}")
    cert.issuer = ca.subject
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + (800 * 86_400)        # Apple: at most 825 days
    ext = OpenSSL::X509::ExtensionFactory.new(cert, ca)
    cert.add_extension(ext.create_extension("basicConstraints", "CA:FALSE", true))
    cert.add_extension(ext.create_extension("keyUsage", "digitalSignature", true))
    cert.add_extension(ext.create_extension("extendedKeyUsage", "serverAuth"))
    cert.add_extension(ext.create_extension("subjectAltName",
                                            (names.map { "DNS:#{it}" } + ips.map { "IP:#{it}" }).join(",")))
    cert.add_extension(ext.create_extension("authorityKeyIdentifier", "keyid"))
    cert.sign(ca_key, OpenSSL::Digest.new("SHA256"))
    dir.join("server-key.pem").tap { it.write(key.to_pem); it.chmod(0o600) }
    dir.join("server.pem").write(cert.to_pem + ca.to_pem)   # chain: the server's, then the CA's

    port = ENV.fetch("SPOTTER_HTTPS_PORT", "3443")
    puts "Server certificate for #{(names + ips).join(', ')}"
    puts "Restart bin/dev, then open https://#{names.first}:#{port} on the laptop."
  end
end
