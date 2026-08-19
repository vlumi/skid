import SkidCore
import SwiftUI

/// Per-seat setup tweaks — split from `CouchGame.swift` on the file-length
/// budget.
extension CouchGame {
    /// Toggle one player's control scheme (Casual ↔ Pro).
    public func toggleScheme(slot: Int) {
        guard schemes.indices.contains(slot) else { return }
        schemes[slot] = schemes[slot] == .casual ? .pro : .casual
    }

    /// Cycle one player's color to the next not taken by anyone else.
    public func cycleColor(slot: Int) {
        guard colorIndices.indices.contains(slot) else { return }
        let taken = Set(colorIndices.enumerated().filter { $0.offset != slot }.map(\.element))
        var next = colorIndices[slot]
        repeat {
            next = (next + 1) % Self.palette.count
        } while taken.contains(next)
        colorIndices[slot] = next
    }
}
