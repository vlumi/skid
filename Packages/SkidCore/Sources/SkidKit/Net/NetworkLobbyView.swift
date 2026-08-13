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
            Color(red: 0.18, green: 0.35, blue: 0.15).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Play together", bundle: .module)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

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
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    net.leave()
                    game.backToSetup()
                } label: {
                    Text("Back", bundle: .module)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
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
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    /// How many people are sitting at THIS phone — the thing that makes two
    /// devices with two players each a four-car race.
    private var seatPicker: some View {
        VStack(spacing: 8) {
            Text("Players on this device", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 10) {
                ForEach(1...RaceRoster.maxSeatsPerDevice, id: \.self) { count in
                    Button {
                        game.playerCount = count
                    } label: {
                        Text("\(count)")
                            .font(.headline)
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
                .font(.headline)
                .foregroundStyle(.white)
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
                        .foregroundStyle(.white)
                        Spacer()
                        Text(entry.seats.map { "\($0.rawValue + 1)" }.joined(separator: ", "))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.subheadline)
                }
            }
            .padding(14)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

            // Guests asking in. The host decides — not security (the field cap
            // bounds who gets in) but so nobody appears unannounced.
            ForEach(net.pendingJoins) { pending in
                HStack(spacing: 10) {
                    Text(verbatim: "\(pending.display) (\(pending.seats))")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        net.approve(pending.peer)
                    } label: {
                        Text("Let in", bundle: .module).font(.subheadline.bold())
                    }
                    Button {
                        net.decline(pending.peer)
                    } label: {
                        Text("No", bundle: .module).font(.subheadline)
                    }
                }
            }

            if let note = net.endedReason {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let note = net.joinNote {
                Text(note)
                    .font(.footnote)
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
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// Pick a race, rather than joining whatever answers first — a room can hold
    /// two of them. Deliberately a plain list: the menus get a real redesign later
    /// and it will replace this.
    private var hostList: some View {
        VStack(spacing: 14) {
            Text("Looking for a race…", bundle: .module)
                .font(.headline)
                .foregroundStyle(.white)
            if let note = net.endedReason {
                Text(note)
                    .font(.footnote)
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
            .font(.headline)
            .foregroundStyle(.white)
    }

    private func ended(_ reason: String?) -> some View {
        VStack(spacing: 14) {
            Text(reason ?? String(localized: "The race ended"))
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button {
                net.leave()
                game.backToSetup()
            } label: {
                label(Text("Done", bundle: .module), filled: true)
            }
        }
    }

    private var connecting: some View {
        Text("Starting…", bundle: .module)
            .font(.headline)
            .foregroundStyle(.white)
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
            tuning: game.settings.carTuning, carContact: game.carContact)
    }

    private func label(_ text: Text, filled: Bool) -> some View {
        text
            .font(.headline)
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
