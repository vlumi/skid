import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// **A track as a square somebody else can point a phone at.**
///
/// CoreImage's own generator, so there is no dependency and nothing to keep in
/// step with a spec. Rendered at the size it will be drawn and with nearest-
/// neighbour scaling: a QR is pixel art, and smoothing its edges is how a code
/// becomes hard to read.
///
/// **Medium error correction.** A signed code is 160–190 characters, which fits
/// comfortably (measured: V8–V9), and medium survives the phone-photographing-a-
/// phone case this exists for. High correction would cost a version or two of
/// density for redundancy that a screen — unlike a printed sticker — does not
/// need.
enum QRCode {
    /// Encode `text` as a QR image `points` wide, or nil if CoreImage refuses
    /// (which it does for input too long to fit any version).
    static func image(for text: String, points: CGFloat) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Scale by whole pixels so every module lands on the same number of
        // them — a fractional scale gives some modules an extra row and reads
        // as a wobbly, harder-to-scan code.
        let scale = max(1, (points / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

/// A QR code as a view, sized to fit and never smoothed.
struct QRCodeView: View {
    let text: String
    var side: CGFloat = 220

    var body: some View {
        Group {
            if let image = QRCode.image(for: text, points: side) {
                Image(decorative: image, scale: 1)
                    // **Nearest neighbour, not the default smoothing.** A QR is
                    // pixel art; interpolating it blurs the module edges that a
                    // scanner is looking for.
                    .interpolation(.none)
                    .resizable()
                    .frame(width: side, height: side)
                    // A quiet zone is part of the spec — a code butted against
                    // dark chrome scans badly, and the white border is what a
                    // scanner uses to find the code at all.
                    .padding(10)
                    .background(.white)
            } else {
                // Longer than any QR version can hold. Rare (a signed code is
                // 160–190 chars against a ~2900 ceiling) but not impossible, and
                // a blank square would read as a bug.
                Text("This track is too long for a QR code.", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(width: side, height: side)
            }
        }
    }
}
