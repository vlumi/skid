import SkidCore
import SwiftUI

/// **Host or join, then wait for the lights.**
///
/// Deliberately plain. This is the spike's UI: its job is to get two phones into
/// one race and to say clearly what is happening when they do not, because
/// "nothing happened" is the failure mode that costs an afternoon to diagnose.
/// A designed lobby comes after the design is known to work.
struct NetworkLobbyView: View {
    @ObservedObject var net: NetworkedGame
    @ObservedObject var game: CouchGame

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Play together", bundle: .module)
                    .font(Retro.font(20, weight: .black))
                    .foregroundStyle(Retro.onGround)

                switch net.phase {
                case .idle: chooser
                case .joining: hostList
                case .awaitingApproval: asking
                case .hosting, .lobby: waiting
                case .racing: connecting
                case .ended(let reason): ended(reason)
                }

                Spacer()

                // The handshake, on screen. Two device sessions were spent on
                // failures whose cause was invisible from the lobby; this is the
                // cheapest way to make the next one diagnosable.
                if !net.trace.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(net.trace.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Retro.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    net.leave()
                    game.backToMenu()
                } label: {
                    Text("Back", bundle: .module)
                        .font(Retro.body)
                        .foregroundStyle(Retro.onGround)
                }
            }
            .padding(28)
        }
    }

    // MARK: - Choosing a side

    private var chooser: some View {
        VStack(spacing: 18) {
            seatPicker
            Button {
                net.host(seats: game.playerCount)
            } label: {
                label(Text("Host a race", bundle: .module), filled: true)
            }
            Button {
                net.join(seats: game.playerCount)
            } label: {
                label(Text("Join a race", bundle: .module), filled: false)
            }
            Text("Both phones need Wi-Fi or Bluetooth on. No router required.", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    /// How many people are sitting at THIS phone — the thing that makes two
    /// devices with two players each a four-car race.
    private var seatPicker: some View {
        VStack(spacing: 8) {
            Text("Players on this device", bundle: .module)
                .font(Retro.body)
                .foregroundStyle(Retro.onGround)
            HStack(spacing: 10) {
                ForEach(1...RaceRoster.maxSeatsPerDevice, id: \.self) { count in
                    Button {
                        game.playerCount = count
                    } label: {
                        Text("\(count)")
                            .font(Retro.body)
                            .frame(width: 46, height: 40)
                            .background(
                                game.playerCount == count
                                    ? Color.white.opacity(0.9) : Color.white.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(game.playerCount == count ? .black : .white)
                    }
                }
            }
        }
    }

    // MARK: - Waiting

    private var waiting: some View {
        VStack(spacing: 16) {
            Text(status)
                .font(Retro.body)
                .foregroundStyle(Retro.onGround)
                .multilineTextAlignment(.center)

            // The roster as everyone will race it — seat numbers included, because
            // a seat number is also a color and a grid slot, and seeing them
            // agree across two screens is half the point of the lobby.
            VStack(spacing: 6) {
                ForEach(net.roster.entries, id: \.peer) { entry in
                    HStack {
                        Text(
                            entry.peer == net.me
                                ? "\(DeviceName.display(entry.peer)) (you)"
                                : DeviceName.display(entry.peer)
                        )
                        .foregroundStyle(Retro.ink)
                        Spacer()
                        Text(entry.seats.map { "\($0.rawValue + 1)" }.joined(separator: ", "))
                            .foregroundStyle(Retro.inkSoft)
                    }
                    .font(Retro.body)
                }
            }
            .padding(14)
            .background(Retro.panel)
            .overlay(RetroBevel(thickness: 2))

            // Guests asking in. The host decides — not security (the field cap
            // bounds who gets in) but so nobody appears unannounced.
            ForEach(net.pendingJoins) { pending in
                HStack(spacing: 10) {
                    Text(verbatim: "\(pending.display) (\(pending.seats))")
                        .font(Retro.body)
                        .foregroundStyle(Retro.onGround)
                    Spacer()
                    Button {
                        net.approve(pending.peer)
                    } label: {
                        Text("Let in", bundle: .module).font(Retro.body)
                    }
                    Button {
                        net.decline(pending.peer)
                    } label: {
                        Text("No", bundle: .module).font(Retro.body)
                    }
                }
            }

            if let note = net.endedReason {
                Text(note)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
            }

            if let note = net.joinNote {
                Text(note)
                    .font(Retro.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if net.isHost {
                Button {
                    start()
                } label: {
                    label(
                        Text(net.canRematch ? "Race again" : "Start race", bundle: .module),
                        filled: true)
                }
                .disabled(net.roster.entries.count < 2)
                .opacity(net.roster.entries.count < 2 ? 0.4 : 1)
            } else {
                Text("Waiting for the host to start…", bundle: .module)
                    .font(Retro.body)
                    .foregroundStyle(Retro.inkSoft)
            }
        }
    }

    /// Pick a race, rather than joining whatever answers first — a room can hold
    /// two of them. Deliberately a plain list: the menus get a real redesign later
    /// and it will replace this.
    private var hostList: some View {
        VStack(spacing: 14) {
            Text("Looking for a race…", bundle: .module)
                .font(Retro.body)
                .foregroundStyle(Retro.onGround)
            if let note = net.endedReason {
                Text(note)
                    .font(Retro.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(net.visibleHosts, id: \.self) { host in
                Button {
                    net.askToJoin(host)
                } label: {
                    label(Text(verbatim: DeviceName.display(host)), filled: true)
                }
            }
        }
    }

    private var asking: some View {
        Text("Asking to join…", bundle: .module)
            .font(Retro.body)
            .foregroundStyle(Retro.onGround)
    }

    private func ended(_ reason: String?) -> some View {
        VStack(spacing: 14) {
            Text(reason ?? String(localized: "The race ended"))
                .font(Retro.body)
                .foregroundStyle(Retro.onGround)
                .multilineTextAlignment(.center)
            Button {
                net.leave()
                game.backToMenu()
            } label: {
                label(Text("Done", bundle: .module), filled: true)
            }
        }
    }

    private var connecting: some View {
        Text("Starting…", bundle: .module)
            .font(Retro.body)
            .foregroundStyle(Retro.onGround)
    }

    private var status: String {
        let seated = net.roster.seatCount
        switch net.phase {
        case .hosting where net.roster.entries.count < 2:
            return String(localized: "Waiting for players to join…")
        case .joining:
            return String(localized: "Looking for a host…")
        default:
            return String(localized: "\(seated) cars ready")
        }
    }

    /// The host picks the track and the seed; everyone else is told.
    private func start() {
        let course: RaceStart.Course = .builtin(game.trackID)
        net.startRace(
            course: course, seed: UInt64.random(in: 0..<UInt64.max),
            laps: CouchGame.networkedLaps,
            // The host's physics go on the wire; guests race the host's car, not
            // whatever their own tuning panel happens to say.
            tuning: game.settings.carTuning)
    }

    private func label(_ text: Text, filled: Bool) -> some View {
        text
            .font(Retro.body)
            .foregroundStyle(filled ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                filled ? Color.white.opacity(0.9) : Color.white.opacity(0.15),
                in: RoundedRectangle(cornerRadius: 10))
    }
}

extension String {
    /// Small shim so the status strings stay in the catalog without a `Text`.
    fileprivate init(localized key: String.LocalizationValue) {
        self.init(localized: key, bundle: .module)
    }
}
