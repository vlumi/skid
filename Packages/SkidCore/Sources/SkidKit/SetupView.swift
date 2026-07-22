import SkidCore
import SwiftUI

/// Pre-race lobby: player count, per-player colors (tap to cycle), contact
/// vs ghost, start. Deliberately minimal — only what a couch session needs.
struct SetupView: View {
    @ObservedObject var game: CouchGame

    var body: some View {
        ZStack {
            Color(red: 0.28, green: 0.55, blue: 0.23).ignoresSafeArea()
            VStack(spacing: 28) {
                Text(verbatim: "SKID")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)

                VStack(spacing: 10) {
                    Text("Players", bundle: .module)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 10) {
                        ForEach(1...4, id: \.self) { count in
                            Button {
                                game.playerCount = count
                            } label: {
                                Text(verbatim: "\(count)")
                                    .font(.title2.bold())
                                    .frame(width: 52, height: 44)
                                    .background(
                                        game.playerCount == count
                                            ? Color.white.opacity(0.9) : .black.opacity(0.25),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .foregroundStyle(
                                        game.playerCount == count ? .black : .white)
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    HStack(spacing: 18) {
                        ForEach(0..<game.playerCount, id: \.self) { slot in
                            Button {
                                game.cycleColor(slot: slot)
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(CouchGame.palette[game.colorIndices[slot]])
                                        .frame(width: 46, height: 46)
                                        .overlay(
                                            Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                                    Text("P\(slot + 1)", bundle: .module)
                                        .font(.caption.bold())
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    modeButton(label: Text("Contact", bundle: .module), contact: true)
                    modeButton(label: Text("Ghost", bundle: .module), contact: false)
                }

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

    private func modeButton(label: Text, contact: Bool) -> some View {
        Button {
            game.carContact = contact
        } label: {
            label
                .font(.callout.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    game.carContact == contact ? Color.white.opacity(0.9) : .black.opacity(0.25),
                    in: Capsule()
                )
                .foregroundStyle(game.carContact == contact ? .black : .white)
        }
    }
}
