import SkidCore
import SwiftUI

/// Pre-race lobby: mode, player count, seating, per-player colors, AI
/// opponents, contact vs ghost, hiscores, start. Deliberately minimal —
/// only what a couch session needs.
struct SetupView: View {
    @ObservedObject var game: CouchGame

    var body: some View {
        ZStack {
            Color(red: 0.28, green: 0.55, blue: 0.23).ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(verbatim: "SKID")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                    hiscoreLine
                }

                HStack(spacing: 10) {
                    choice(Text("Race", bundle: .module), selected: game.mode == .race) {
                        game.mode = .race
                    }
                    choice(
                        Text("Time trial", bundle: .module), selected: game.mode == .timeTrial
                    ) {
                        game.mode = .timeTrial
                    }
                }

                if game.mode == .race {
                    raceOptions
                }

                colorRow

                Button {
                    game.startRace()
                } label: {
                    Text("Start", bundle: .module)
                        .font(.title.bold())
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.92), in: Capsule())
                        .foregroundStyle(.black)
                }
            }
        }
    }

    @ViewBuilder private var hiscoreLine: some View {
        let best = game.hiscores.best(for: TrackLibrary.practiceLoop().id)
        HStack(spacing: 14) {
            if let lap = best.bestLapTicks {
                Text("Best lap \(formatTicks(lap))", bundle: .module)
            }
            if let race = best.raceTicks {
                Text("Best race \(formatTicks(race))", bundle: .module)
            }
        }
        .font(.footnote.monospacedDigit().bold())
        .foregroundStyle(.white.opacity(0.85))
    }

    @ViewBuilder private var raceOptions: some View {
        VStack(spacing: 14) {
            labeledRow(Text("Players", bundle: .module)) {
                ForEach(1...4, id: \.self) { count in
                    squareChoice(String(count), selected: game.playerCount == count) {
                        game.playerCount = count
                    }
                }
            }
            if game.playerCount == 2 {
                HStack(spacing: 10) {
                    choice(
                        Text("Side-by-side", bundle: .module), selected: !game.faceToFace
                    ) {
                        game.faceToFace = false
                    }
                    choice(Text("Face-to-face", bundle: .module), selected: game.faceToFace) {
                        game.faceToFace = true
                    }
                }
            }
            if game.playerCount == 3 {
                openCornerPicker
            }
            if game.playerCount < 4 {
                labeledRow(Text("AI", bundle: .module)) {
                    ForEach(0...(4 - game.playerCount), id: \.self) { count in
                        squareChoice(String(count), selected: game.aiCount == count) {
                            game.aiCount = count
                        }
                    }
                }
            }
            if game.aiCount > 0 {
                HStack(spacing: 10) {
                    choice(
                        Text("Easy", bundle: .module),
                        selected: game.aiDifficulty == .easy
                    ) {
                        game.aiDifficulty = .easy
                    }
                    choice(
                        Text("Medium", bundle: .module),
                        selected: game.aiDifficulty == .medium
                    ) {
                        game.aiDifficulty = .medium
                    }
                    choice(
                        Text("Hard", bundle: .module),
                        selected: game.aiDifficulty == .hard
                    ) {
                        game.aiDifficulty = .hard
                    }
                }
            }
            HStack(spacing: 10) {
                choice(Text("Contact", bundle: .module), selected: game.carContact) {
                    game.carContact = true
                }
                choice(Text("Ghost", bundle: .module), selected: !game.carContact) {
                    game.carContact = false
                }
            }
        }
    }

    /// 3P seating: a 2×2 mini-map of the screen; tap the quadrant that
    /// should stay open (marked ×), the rest get the players in order.
    @ViewBuilder private var openCornerPicker: some View {
        VStack(spacing: 6) {
            Text("Open corner", bundle: .module)
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(0.85))
            let grid: [[ZoneCorner]] = [[.topLeft, .topRight], [.bottomLeft, .bottomRight]]
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(grid[row], id: \.self) { corner in
                            let isOpen = game.openCorner == corner
                            Button {
                                game.openCorner = corner
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            isOpen
                                                ? Color.black.opacity(0.4)
                                                : .white.opacity(0.85))
                                    if isOpen {
                                        Text(verbatim: "×")
                                            .font(.headline)
                                            .foregroundStyle(.white.opacity(0.8))
                                    } else if let slot = slotIndex(for: corner) {
                                        Circle()
                                            .fill(CouchGame.palette[game.colorIndices[slot]])
                                            .frame(width: 16, height: 16)
                                    }
                                }
                                .frame(width: 64, height: 40)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Which player slot a corner gets in the 3P layout (zones fill in
    /// bottom-left → bottom-right → top-left → top-right order, skipping
    /// the open corner).
    private func slotIndex(for corner: ZoneCorner) -> Int? {
        ZoneCorner.allCases.filter { $0 != game.openCorner }.firstIndex(of: corner)
    }

    @ViewBuilder private var colorRow: some View {
        HStack(spacing: 18) {
            let humans = game.mode == .timeTrial ? 1 : game.playerCount
            ForEach(0..<humans, id: \.self) { slot in
                Button {
                    game.cycleColor(slot: slot)
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(CouchGame.palette[game.colorIndices[slot]])
                            .frame(width: 46, height: 46)
                            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                        Text("P\(slot + 1)", bundle: .module)
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    private func labeledRow(_ label: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 8) {
            label
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 10, content: content)
        }
    }

    private func choice(_ label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.callout.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    selected ? Color.white.opacity(0.9) : .black.opacity(0.25), in: Capsule()
                )
                .foregroundStyle(selected ? .black : .white)
        }
    }

    private func squareChoice(
        _ label: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.title3.bold())
                .frame(width: 48, height: 40)
                .background(
                    selected ? Color.white.opacity(0.9) : .black.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .foregroundStyle(selected ? .black : .white)
        }
    }
}
