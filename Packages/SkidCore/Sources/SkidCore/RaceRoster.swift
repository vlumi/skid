import Foundation

/// **Who is racing, which device owns them, and what number each one is.**
///
/// A device is not a player — it is *a screen with some players sitting at it*.
/// `CouchRig` already maps N seats to one screen, so two phones with two players
/// each is a four-player race, which is a better party than four phones.
///
/// The roster is what makes that safe. Seat numbering is **global**, assigned by
/// the host at join time: two phones each thinking they own seats 0–1 is the first
/// bug this design would hit, and every car would then be driven by two thumbs.
/// Seats are handed out in join order and never renumbered, because a seat number
/// is also a color, a HUD chip and a grid slot.
///
/// It is deliberately transport-free — a peer is a `String`, so the same roster
/// works over MultipeerConnectivity or the UDP escape hatch, and it is testable
/// without either.
public struct RaceRoster: Equatable, Sendable, Codable {
    /// Whatever the transport calls a device. Opaque here on purpose.
    public typealias PeerName = String

    /// One device's claim: the peer, and how many seats it brings.
    public struct Entry: Equatable, Sendable, Codable {
        public let peer: PeerName
        /// Global seat numbers this device drives, in its own local order — so
        /// entry.seats[0] is that device's first control band.
        public let seats: [PlayerID]

        public init(peer: PeerName, seats: [PlayerID]) {
            self.peer = peer
            self.seats = seats
        }
    }

    /// Devices in join order. The first is the host.
    public private(set) var entries: [Entry] = []

    /// The next global seat number to hand out — **monotonic**, never reused.
    ///
    /// Persisted rather than derived, because it has to outlive the entries it
    /// counted: a device leaving must not free its numbers for the next joiner
    /// while anyone else is still driving a higher one.
    private var nextSeatNumber = 0

    /// Total cars, which is what `Race` is built with.
    public var seatCount: Int { entries.reduce(0) { $0 + $1.seats.count } }

    /// Every seat in global order — the `players` array for `Race` and the order
    /// `LockstepClock` waits on.
    public var seats: [PlayerID] { entries.flatMap(\.seats).sorted() }

    /// Devices, in join order. The host is first.
    public var peers: [PeerName] { entries.map(\.peer) }

    /// The host — whoever created the race. Nil only for an empty roster.
    public var host: PeerName? { entries.first?.peer }

    public init() {}

    // MARK: - Building it

    /// Why a device could not be seated. A join that fails needs a reason a lobby
    /// can show, not a silent no-op.
    public enum JoinError: Error, Equatable, Sendable {
        /// The field is full. `available` is what would have fit.
        case fieldFull(requested: Int, available: Int)
        /// This device is already in the roster. Re-joining would double its cars.
        case alreadyJoined(PeerName)
        /// A device must bring at least one seat, and no more than a rig lays out.
        case seatCountOutOfRange(requested: Int, max: Int)
    }

    /// Seat a device, returning the global seat numbers it was given.
    ///
    /// **Seats are appended, never reused.** A device that leaves does not free its
    /// numbers for the next joiner mid-race — see `remove(peer:)` for why.
    @discardableResult
    public mutating func join(_ peer: PeerName, seats requested: Int) throws -> [PlayerID] {
        guard requested >= 1, requested <= Self.maxSeatsPerDevice else {
            throw JoinError.seatCountOutOfRange(requested: requested, max: Self.maxSeatsPerDevice)
        }
        guard !entries.contains(where: { $0.peer == peer }) else {
            throw JoinError.alreadyJoined(peer)
        }
        let available = Self.maxSeats - seatCount
        guard requested <= available else {
            throw JoinError.fieldFull(requested: requested, available: available)
        }
        // **Numbered from the highest ever issued, not from the current count.**
        // `seatCount` shrinks when a device leaves, so basing the next seat on it
        // hands out a number somebody else is still driving: with a, b, c joined
        // and `a` gone, a fourth device got seats 1,2,3 — colliding with b at 2.
        // Exactly the two-thumbs-one-car bug the roster exists to prevent, and it
        // took the round-trip test to surface it.
        let assigned = (0..<requested).map { PlayerID(nextSeatNumber + $0) }
        entries.append(Entry(peer: peer, seats: assigned))
        nextSeatNumber += requested
        return assigned
    }

    /// Drop a device — it walked out of range, or backed out of the lobby.
    ///
    /// **Remaining seats keep their numbers.** Compacting them would renumber
    /// somebody else's car mid-lobby, changing their color and their grid slot;
    /// and if this ever runs mid-race it would be a different race on every peer.
    /// So the seat list can have holes, which is why `seats` is derived from the
    /// entries rather than assumed to be `0..<count`.
    public mutating func remove(peer: PeerName) {
        entries.removeAll { $0.peer == peer }
    }

    /// The seats a given device drives — its own thumbs.
    public func seats(for peer: PeerName) -> [PlayerID] {
        entries.first { $0.peer == peer }?.seats ?? []
    }

    /// The device driving a seat, for "waiting for Ville's phone" chrome.
    public func peer(driving seat: PlayerID) -> PeerName? {
        entries.first { $0.seats.contains(seat) }?.peer
    }

    // MARK: - Caps

    /// Total cars a networked race allows.
    ///
    /// Nine, matching the grid and the palette (both reach it comfortably — see
    /// the start-grid work). This is the *protocol's* ceiling, deliberately not the
    /// soft cap: `CouchGame.maxCars` limits what the local UI offers today for
    /// performance reasons, and a protocol maximum has to be chosen once because
    /// retrofitting one is worse than picking it.
    public static let maxSeats = PieceCompiler.Grid.slots

    /// Seats one device may bring — what a `CouchRig` lays out around one map
    /// (four control bands) and what fits a phone.
    ///
    /// Lives here rather than in SkidKit because it is a *protocol* limit: a peer
    /// announces how many seats it brings, and the host has to validate that claim
    /// without knowing anything about the joiner's UI. `CouchGame.maxLocalPlayers`
    /// reads from this, not the reverse — SkidCore cannot see SkidKit, and the
    /// dependency runs the right way round anyway.
    public static let maxSeatsPerDevice = 4
}
