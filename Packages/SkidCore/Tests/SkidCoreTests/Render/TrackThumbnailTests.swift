import Foundation
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **Previews are drawn from the track, so they cannot disagree with it.**
///
/// What is testable here is the *sourcing* — that a row finds the right layout, whichever
/// kind of track it is — and the shared fit. The drawing itself is a `Canvas` closure and
/// goes on device; a wrong preview is visible in a way no assertion improves on.
@MainActor
final class TrackThumbnailTests: XCTestCase {
    /// A built-in resolves from the library's own codes, so the browser needs no separate
    /// table of them.
    func testABuiltinResolvesToALayout() throws {
        for builtin in TrackLibrary.builtins {
            let layout = TrackThumbnail.layout(forTrackID: builtin.id, library: TrackLibraryBook())
            XCTAssertNotNil(layout, "\(builtin.id) has no previewable layout")
            XCTAssertFalse(layout?.pieces.isEmpty ?? true)
        }
    }

    /// A player's track resolves from the book — the same call, so a caller never has to
    /// know which kind it is holding.
    func testALibraryEntryResolvesToALayout() throws {
        var book = TrackLibraryBook()
        let code = TrackLibrary.builtins[0].code
        let entry = TrackLibraryBook.Entry(
            name: "Mine", code: code, isRaceable: true,
            createdAt: Date(), updatedAt: Date())
        book.put(entry)
        let layout = TrackThumbnail.layout(forTrackID: entry.trackID, library: book)
        XCTAssertNotNil(layout)
    }

    /// **An unknown id is nil, not a crash.** The browser draws a blank tile for it: one
    /// unresolvable row is not worth a dialog, and the name still selects.
    func testAnUnknownTrackHasNoLayout() {
        XCTAssertNil(
            TrackThumbnail.layout(forTrackID: "no-such-track", library: TrackLibraryBook()))
    }

    /// A code that will not decode is nil rather than throwing through the view body.
    func testAnUndecodableEntryHasNoLayout() {
        var book = TrackLibraryBook()
        let entry = TrackLibraryBook.Entry(
            name: "Broken", code: "!!!not-base64!!!", isRaceable: true,
            createdAt: Date(), updatedAt: Date())
        book.put(entry)
        XCTAssertNil(TrackThumbnail.layout(forTrackID: entry.trackID, library: book))
    }

    /// **The fit frames a track the same way for the editor and a thumbnail.**
    ///
    /// Shared rather than reimplemented so a preview cannot show the author something
    /// other than what they built. Asserted through the numbers: the footprint is padded
    /// by the road's half-width, and the scale lands it inside the box.
    func testTheFitCentersAndScalesToTheBox() throws {
        let layout = try XCTUnwrap(TrackLibrary.layout(id: "oval"))
        let walk = layout.walk()
        let box = EditorRenderer.footprint(of: walk)
        XCTAssertGreaterThan(box.width, 0)
        XCTAssertGreaterThan(box.height, 0)

        // **The footprint is padded by the road's half-width.** Without it the box
        // bounds the CENTERLINE, so half the road hangs outside the frame and the
        // track's edges are clipped. Asserted against the bare centerline extent,
        // which is what the padding is added to.
        let centers = walk.placed.flatMap { placed in
            placed.piece.paths.indices.flatMap { placed.centerlineSamples(path: $0) }
        }
        let half = Double(PieceCatalog.width) / 2
        let spanX = (centers.map(\.x).max() ?? 0) - (centers.map(\.x).min() ?? 0)
        XCTAssertEqual(
            box.width, spanX + 2 * half, accuracy: 0.001,
            "the footprint is not padded by the road's half-width; edges will clip")

        let view = CGSize(width: 200, height: 120)
        let margin: CGFloat = 4
        let fit = EditorRenderer.fit(walk: walk, in: view, margin: margin)
        // The whole footprint lands inside the view, allowing for the margin.
        let drawnWidth = box.width * fit.scale
        let drawnHeight = box.height * fit.scale
        XCTAssertLessThanOrEqual(drawnWidth, view.width - 2 * margin + 0.001)
        XCTAssertLessThanOrEqual(drawnHeight, view.height - 2 * margin + 0.001)
        // …and touches one of the two limits, or it is not a *fit*.
        let fillsWidth = abs(drawnWidth - (view.width - 2 * margin)) < 0.001
        let fillsHeight = abs(drawnHeight - (view.height - 2 * margin)) < 0.001
        XCTAssertTrue(fillsWidth || fillsHeight, "the fit left slack on both axes")

        // Centered: the footprint's middle maps to the view's middle.
        let center = fit.screen(Vec2(box.midX, box.midY))
        XCTAssertEqual(center.x, view.width / 2, accuracy: 0.001)
        XCTAssertEqual(center.y, view.height / 2, accuracy: 0.001)
    }

    /// Zoom and pan are the editor's, and a thumbnail passing neither gets the plain fit —
    /// which is what keeps the two framings identical.
    func testZoomAndPanDefaultToNothing() throws {
        let walk = try XCTUnwrap(TrackLibrary.layout(id: "oval")).walk()
        let view = CGSize(width: 300, height: 300)
        let plain = EditorRenderer.fit(walk: walk, in: view)
        let explicit = EditorRenderer.fit(walk: walk, in: view, zoom: 1, pan: .zero)
        XCTAssertEqual(plain.scale, explicit.scale)
        XCTAssertEqual(plain.offset.width, explicit.offset.width)

        let zoomed = EditorRenderer.fit(walk: walk, in: view, zoom: 2)
        XCTAssertEqual(zoomed.scale, plain.scale * 2, accuracy: 0.0001)
    }
}
