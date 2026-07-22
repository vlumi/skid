// Renders the app icon (AppIconScene, the game's own drawing code) to a
// 1024×1024 PNG. Run via `make icon`; macOS-only tooling.

#if os(macOS)
import ImageIO
import SkidKit
import SwiftUI
import UniformTypeIdentifiers

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
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
    let url = URL(fileURLWithPath: path)
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        fatalError("cannot open \(path) for writing")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("failed to finalize \(path)")
    }
    print("wrote \(url.path)")
}

await MainActor.run { renderIcon() }
#endif
