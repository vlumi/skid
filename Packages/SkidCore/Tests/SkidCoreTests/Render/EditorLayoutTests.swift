import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **When the editor docks its tools beside the map.** The phone column fits a
/// tall, narrow screen; a Mac window or an iPad gets the tools on the map's
/// edges — but a phone held sideways, wide yet short, keeps its column, since
/// the docks would not fit beside a usable map.
@MainActor
final class EditorLayoutTests: XCTestCase {
    func testWhoGetsTheDocks() {
        let docked: [String: CGSize] = [
            "iPad mini, portrait": CGSize(width: 744, height: 1133),
            "iPad, landscape": CGSize(width: 1180, height: 820),
            "Mac window, default": CGSize(width: 1280, height: 860),
            "Mac window, minimum": CGSize(width: 900, height: 640),
        ]
        let column: [String: CGSize] = [
            "iPhone SE": CGSize(width: 375, height: 667),
            "iPhone 17 Pro Max": CGSize(width: 440, height: 956),
            "iPhone sideways": CGSize(width: 956, height: 440),
        ]
        for (name, size) in docked { XCTAssertTrue(EditorView.usesDocks(in: size), name) }
        for (name, size) in column { XCTAssertFalse(EditorView.usesDocks(in: size), name) }
    }
}
