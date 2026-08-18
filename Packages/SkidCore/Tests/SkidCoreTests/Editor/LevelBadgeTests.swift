import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **The Levels mode works from the first piece, focuses to one storey, and never
/// stacks two numbers on one spot.** All three were reported from device: the
/// button did nothing on a flat track (so it could not be kept on from the start
/// of a tall build), level 0 got no badge, and crossings drew both storeys'
/// numbers on top of each other.
@MainActor
final class LevelBadgeTests: XCTestCase {
    private var flatWalk: WalkResult {
        TrackLayout(pieces: [PieceCatalog.startPieceID, 1, 1, 1]).walk()
    }

    private var transform: EditorRenderer.Transform {
        EditorRenderer.Transform(scale: 1, offset: .zero)
    }

    /// In Levels mode every piece is badged — level 0 included, so the mode says
    /// something on a track that has not climbed yet.
    func testAFlatTrackBadgesEveryPieceWithZero() {
        let badges = EditorRenderer.levelBadges(
            walk: flatWalk,
            query: .init(blockedPieces: [], showLevels: true, onlyLevel: nil),
            transform: transform)
        XCTAssertEqual(badges.count, flatWalk.placed.count)
        XCTAssertTrue(badges.allSatisfy { $0.level == 0 && !$0.blocked })
    }

    /// Mode off: only the blocked warnings show, exactly as before.
    func testModeOffShowsOnlyWarnings() {
        let badges = EditorRenderer.levelBadges(
            walk: flatWalk,
            query: .init(blockedPieces: [2], showLevels: false, onlyLevel: nil),
            transform: transform)
        XCTAssertEqual(badges.count, 1)
        XCTAssertTrue(badges[0].blocked)
    }

    /// Focused on one storey, the other storeys' numbers disappear — but a blocked
    /// warning is never filtered, since it shows even with the mode off.
    func testAStoreyFocusHidesTheOtherLevels() {
        let none = EditorRenderer.levelBadges(
            walk: flatWalk,
            query: .init(blockedPieces: [], showLevels: true, onlyLevel: 1),
            transform: transform)
        XCTAssertTrue(none.isEmpty, "a flat track has nothing on level 1")
        let warned = EditorRenderer.levelBadges(
            walk: flatWalk,
            query: .init(blockedPieces: [3], showLevels: true, onlyLevel: 1),
            transform: transform)
        XCTAssertEqual(warned.count, 1)
        XCTAssertTrue(warned[0].blocked, "the warning must survive the focus")
    }

    /// The plan itself never keeps two badges on one spot — asked of a REAL
    /// bridged layout (the clover), so unwiring the cover pass from the plan
    /// fails here even though `dropCovered` alone still works.
    func testTheCloverPlanKeepsItsBadgesApart() throws {
        let clover = try XCTUnwrap(TrackLibrary.builtins.first { $0.id == "clover" })
        let walk = try TrackCode.decode(clover.code).walk()
        let badges = EditorRenderer.levelBadges(
            walk: walk,
            query: .init(blockedPieces: [], showLevels: true, onlyLevel: nil),
            transform: transform)
        XCTAssertGreaterThan(badges.count, 10, "the clover should badge broadly")
        let minDistance = 7.0 * 2.1  // scale 1 → radius 7, the plan's own spacing
        for (index, badge) in badges.enumerated() {
            for other in badges.dropFirst(index + 1) where !badge.blocked && !other.blocked {
                XCTAssertGreaterThanOrEqual(
                    hypot(badge.at.x - other.at.x, badge.at.y - other.at.y), minDistance,
                    "two badges share a spot at \(badge.at)")
            }
        }
    }

    /// **The mode is reachable on a flat track** — the reported bug was a Levels
    /// button that did nothing until something reached level 1, so it could not
    /// be kept on from the start of a tall build. And on a flat track the cycle
    /// skips the single-storey filter, which would add nothing over `all`.
    func testTheCycleWorksOnAFlatTrack() {
        typealias Filter = EditorView.LevelFilter
        XCTAssertEqual(Filter.off.next(usedLevels: [0]), .all, "the mode must turn on")
        XCTAssertEqual(Filter.all.next(usedLevels: [0]), .off)
        // With storeys in use, `all` steps into the per-storey walk.
        XCTAssertEqual(Filter.off.next(usedLevels: [0, 1, 2]), .all)
        XCTAssertEqual(Filter.all.next(usedLevels: [0, 1, 2]), .storey(0))
        XCTAssertEqual(Filter.storey(0).next(usedLevels: [0, 1, 2]), .storey(1))
        XCTAssertEqual(Filter.storey(2).next(usedLevels: [0, 1, 2]), .off)
    }

    /// **The long-press jump list offers every state the cycle walks** — off,
    /// all, then each used storey — and skips the single storey of a flat track
    /// exactly as the cycle does, so the two entrances can never disagree.
    func testTheJumpListMatchesTheCycle() {
        typealias Filter = EditorView.LevelFilter
        XCTAssertEqual(Filter.pickerOptions(usedLevels: [0]), [.off, .all])
        XCTAssertEqual(
            Filter.pickerOptions(usedLevels: [0, 1, 3]),
            [.off, .all, .storey(0), .storey(1), .storey(3)])
        // Agreement, mechanically: from every option, cycling stays inside the list.
        let used = [0, 1, 2]
        for option in Filter.pickerOptions(usedLevels: used) {
            XCTAssertTrue(
                Filter.pickerOptions(usedLevels: used).contains(option.next(usedLevels: used)),
                "the cycle left the jump list from \(option)")
        }
    }

    /// Where badges land on one spot, only the top-most level survives; warnings
    /// are never dropped and cover plain numbers under them.
    func testACoveredBadgeIsDropped() {
        typealias Badge = EditorRenderer.LevelBadge
        let stacked = [
            Badge(at: CGPoint(x: 100, y: 100), level: 0, blocked: false),
            Badge(at: CGPoint(x: 104, y: 102), level: 1, blocked: false),
            Badge(at: CGPoint(x: 300, y: 300), level: 0, blocked: false),
        ]
        let kept = EditorRenderer.dropCovered(stacked, minDistance: 20)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(kept.filter { $0.at.x < 200 }.map(\.level), [1], "the lower number stayed")
        // A warning wins the spot even against a higher plain number.
        let warned = [
            Badge(at: CGPoint(x: 100, y: 100), level: 2, blocked: false),
            Badge(at: CGPoint(x: 103, y: 100), level: 0, blocked: true),
        ]
        XCTAssertEqual(
            EditorRenderer.dropCovered(warned, minDistance: 20).map(\.blocked), [true])
    }
}
