# A QR code as inline SVG (rqrcode): dark modules on white with the 4-module
# quiet zone scanners need - white even in dark mode. The URL is uppercased so
# the whole code fits alphanumeric mode (Shotmetrix accepts that; a Shotmetrix
# code is then always version 24, 113 x 113).
class QrCodeComponent < ApplicationComponent
  def initialize(text:, label:, level: :l)
    @text, @label, @level = text, label, level
  end

  def call
    qr = RQRCode::QRCode.new(@text.upcase, level: @level, mode: :alphanumeric)
    svg = qr.as_svg(module_size: 4, offset: 16, color: "000", fill: "fff", use_path: true, viewbox: true, standalone: true)
    tag.div(svg.html_safe, role: "img", "aria-label": @label, data: { qr_version: qr.qrcode.version },
            class: "mx-auto aspect-square w-full max-w-[28rem] rounded-md bg-white [&>svg]:size-full")
  end
end
