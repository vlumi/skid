// Renders the app icon (AppIconScene, the game's own drawing code) to a
// 1024×1024 PNG. Run via `make icon`; macOS-only tooling.
//
// App Store Connect REJECTS app icons that carry an alpha channel — a
// transparent icon silently fails to show up in ASC. SwiftUI's
// ImageRenderer.cgImage always produces an RGBA image (alpha present even
// when the scene fills the frame opaquely), so we must flatten it onto an
// OPAQUE bitmap before writing, or the transparency comes back every run.
// This is the whole reason `flattened(_:)` exists — do not write the
// renderer's cgImage straight to PNG.

#if os(macOS)
import CoreGraphics
import ImageIO
import SkidKit
import SwiftUI
import UniformTypeIdentifiers

/// Redraw `image` onto an opaque RGB context so the PNG has NO alpha channel
/// (ASC requirement). A white backdrop fills any pixel the scene didn't
/// cover — the icon art is expected to be full-bleed, so this is only a
/// safety floor, never visible.
@MainActor
func flattened(_ image: CGImage) -> CGImage {
    let side = image.width
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            // .noneSkipLast = opaque RGB, no alpha channel in the output.
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else {
        fatalError("cannot create opaque icon context")
    }
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(rect)
    context.draw(image, in: rect)
    guard let opaque = context.makeImage() else {
        fatalError("cannot flatten icon to an opaque image")
    }
    return opaque
}

@MainActor
func renderIcon() {
    let side: CGFloat = 1024
    let renderer = ImageRenderer(
        content: AppIconScene().frame(width: side, height: side))
    renderer.proposedSize = ProposedViewSize(width: side, height: side)
    renderer.scale = 1
    guard let image = renderer.cgImage else {
        fatalError("icon render produced no image")
    }
    // Strip the alpha channel — ASC rejects icons with transparency.
    let opaque = flattened(image)
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
    let url = URL(fileURLWithPath: path)
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        fatalError("cannot open \(path) for writing")
    }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("failed to finalize \(path)")
    }
    print("wrote \(url.path)")
}

await MainActor.run { renderIcon() }
#endif
