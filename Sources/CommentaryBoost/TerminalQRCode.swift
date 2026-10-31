import CoreImage

/// Renders `text` as a QR code with half-block characters, two modules per character row.
/// Colors are set explicitly (black on white) so it scans on dark terminal themes too.
func terminalQRCode(_ text: String) -> String? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let image = filter.outputImage,
          let cgImage = CIContext().createCGImage(image, from: image.extent) else { return nil }

    // The generator draws one pixel per module; read them back as grayscale.
    let width = cgImage.width, height = cgImage.height
    var pixels = [UInt8](repeating: 255, count: width * height)
    let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drew else { return nil }

    let quiet = 2  // extra white border, on top of the generator's own margin
    func dark(_ x: Int, _ y: Int) -> Bool {
        let (px, py) = (x - quiet, y - quiet)
        guard px >= 0, py >= 0, px < width, py < height else { return false }
        return pixels[py * width + px] < 128
    }

    let colors = "\u{1B}[38;5;16;48;5;231m", reset = "\u{1B}[0m"
    var lines: [String] = []
    for y in stride(from: 0, to: height + 2 * quiet, by: 2) {
        var line = colors
        for x in 0..<(width + 2 * quiet) {
            switch (dark(x, y), dark(x, y + 1)) {
            case (true, true): line += "█"
            case (true, false): line += "▀"
            case (false, true): line += "▄"
            case (false, false): line += " "
            }
        }
        lines.append(line + reset)
    }
    return lines.joined(separator: "\n")
}
