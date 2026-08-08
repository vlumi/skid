import Foundation
import Testing
@testable import SkidCore

struct ZProbe {
    @Test func probe() {
        typealias G = PieceCompiler.Grid
        print("PROBE slots=\(G.slots) depth=\(G.depth) (start piece is \(PieceCatalog.straight))")
        for n in 1...9 {
            print("PROBE \(n) cars -> rows \(G.rows(for: n))")
        }
        // Every slot on the asphalt, for a full field?
        let t = TrackLibrary.track(id: "eight")
        print("PROBE track has \(t.startSlots.count) slots")
        for (i, s) in t.startSlots.enumerated() {
            let surf = t.surface(at: s, height: t.startHeight)
            let d = t.distanceToCenterline(s, height: t.startHeight)
            print("PROBE slot \(i): surface=\(surf) distToCentre=\(String(format: "%.0f", d)) halfW=\(Int(t.halfWidth(atHeight: t.startHeight)))")
        }
    }
}
