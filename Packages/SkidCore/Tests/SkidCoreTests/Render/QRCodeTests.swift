import CoreImage
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **A QR code nobody can scan is a picture of a bug.**
///
/// So these do not check that an image came back — they DECODE it, with
/// CoreImage's own detector, and compare what comes out with what went in. The
/// encoder is a few lines; the thing worth pinning is that a real signed track
/// code survives being turned into a square and read back.
final class QRCodeTests: XCTestCase {
    /// What a detector reads out of a rendered QR, or nil.
    private func decode(_ image: CGImage) -> String? {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return (features.compactMap { $0 as? CIQRCodeFeature }.first)?.messageString
    }

    func testAShortStringRoundTrips() throws {
        let image = try XCTUnwrap(QRCode.image(for: "hello", points: 200))
        XCTAssertEqual(decode(image), "hello")
    }

    /// **Every built-in as a full share link**, which is the real payload: a link
    /// is longer than a bare code, and length is what decides whether a QR fits.
    func testEveryBuiltInSurvivesAsAScannableLink() throws {
        for builtin in TrackLibrary.builtins {
            let url = try XCTUnwrap(TrackLink.url(code: builtin.code, name: builtin.name))
            let text = url.absoluteString
            let image = try XCTUnwrap(
                QRCode.image(for: text, points: 240), "\(builtin.name) produced no QR")
            XCTAssertEqual(decode(image), text, "\(builtin.name) did not scan back")
        }
    }

    /// A SIGNED code is the long case the plan measured at 160–190 characters —
    /// the one that decides whether QR is viable at all.
    func testASignedLengthCodeStillFits() throws {
        // A stand-in of the measured worst case: the longest built-in plus a
        // signature-sized tail.
        let longest = TrackLibrary.builtins.map(\.code).max { $0.count < $1.count } ?? ""
        let signed = longest + String(repeating: "A", count: 140)
        let url = try XCTUnwrap(TrackLink.url(code: signed))
        let text = url.absoluteString
        XCTAssertGreaterThan(text.count, 160, "fixture: not actually the long case")
        let image = try XCTUnwrap(QRCode.image(for: text, points: 240))
        XCTAssertEqual(decode(image), text, "a signed-length link did not scan back")
    }

    /// Scaled by whole pixels, so every module is the same size — a fractional
    /// scale gives some modules an extra row and reads as a wobbly code.
    func testTheImageScalesByWholeModules() throws {
        let image = try XCTUnwrap(QRCode.image(for: "hello", points: 200))
        // CoreImage's raw output is one pixel per module; the scaled width must
        // therefore be a whole multiple of it.
        let raw = try XCTUnwrap(QRCode.image(for: "hello", points: 1))
        XCTAssertEqual(image.width % raw.width, 0, "the QR was scaled fractionally")
    }
}
