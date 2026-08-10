import Foundation
import MultipeerConnectivity
import SkidCore

#if canImport(UIKit)
import UIKit
#endif

/// **MultipeerConnectivity, wrapped down to `RaceTransport`.**
///
/// Chosen because it is *not* LAN-only: it uses infrastructure Wi-Fi when peers
/// share a network and falls back to peer-to-peer Wi-Fi or Bluetooth when they do
/// not, so two phones on a train still find each other. For a couch game that
/// matters more than throughput.
///
/// What it costs: an opaque transport (reliable and unreliable sends, not a
/// socket), a discovery model you do not fully control, and a practical ceiling
/// around eight peers. None of those bind us — the protocol's cap is nine seats
/// across up to nine devices, and a couch has two or three.
///
/// **Everything crossing into the app is hopped to the main actor.** MC calls its
/// delegate on private queues, and the race state it feeds is main-actor-confined;
/// letting a packet mutate the sim from a background queue is a data race that
/// would look exactly like a determinism bug.
///
/// **And nothing goes the other way on the main thread.** Every call INTO MC —
/// send, disconnect, start/stop advertising and browsing, invite — is synchronous
/// and can block while the transport does its work. Three separate device sessions
/// were lost to this: a frozen lobby, an unresponsive Back button, and a "Start
/// race" that wedged the UI before it could redraw. The logic tests cannot see any
/// of it, because they replace this whole class with nothing.
///
/// So they all go through `sendQueue`, which is **serial** — reliable messages must
/// keep their order, or a `RosterUpdate` could overtake the `RaceStart` that froze
/// it and leave the peers disagreeing about who is racing.
public final class MultipeerTransport: NSObject, RaceTransport {
    /// Bonjour service type. Must match the `NSBonjourServices` entry in
    /// Info.plist or iOS 14+ silently refuses to browse — a failure that looks
    /// like "no peers found" rather than an error.
    ///
    /// 15 characters max, lowercase, letters/digits/hyphens only.
    public static let serviceType = "skid-race"

    public let me: RaceRoster.PeerName
    public weak var delegate: RaceTransportDelegate?

    private let localPeer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    public init(displayName: String) {
        // MC truncates display names past 63 bytes and throws on empty ones.
        let trimmed = String(displayName.prefix(60))
        localPeer = MCPeerID(displayName: trimmed.isEmpty ? "Skid" : trimmed)
        me = localPeer.displayName
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    public var connectedPeers: [RaceRoster.PeerName] {
        session.connectedPeers.map(\.displayName)
    }

    // MARK: - Discovery

    /// Host: advertise and accept anyone who asks.
    ///
    /// Auto-accept is deliberate for a couch game — an invitation dialog on a phone
    /// being held by somebody already sitting next to you is friction, not security,
    /// and the roster's field cap is what actually bounds who gets in.
    public func startHosting() {
        stopDiscovery()
        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeer, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        Self.sendQueue.async { advertiser.startAdvertisingPeer() }
    }

    /// Guest: look for a host and invite ourselves in.
    public func startBrowsing() {
        stopDiscovery()
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        browser.delegate = self
        self.browser = browser
        Self.sendQueue.async { browser.startBrowsingForPeers() }
    }

    /// Stop looking, but stay connected — called once the race starts, so a
    /// latecomer cannot join mid-race and discovery stops costing radio.
    public func stopDiscovery() {
        // Same reasoning as `disconnect()`: stopping the radio can block, and
        // nothing here needs to happen before the next line of UI code runs.
        let advertiser = advertiser
        let browser = browser
        self.advertiser = nil
        self.browser = nil
        guard advertiser != nil || browser != nil else { return }
        Self.sendQueue.async {
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
        }
    }

    public func disconnect() {
        stopDiscovery()
        // **Off the main thread.** `MCSession.disconnect()` and the advertiser and
        // browser teardowns can block while the transport unwinds its connections,
        // and this is called from a button action — a UI that stops responding to
        // "Back" is exactly what that looks like. The session is retained by the
        // closure, so it outlives this call.
        let session = session
        Self.sendQueue.async { session.disconnect() }
    }

    // MARK: - Sending

    public func send(_ bytes: [UInt8], reliable: Bool) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        let data = Data(bytes)
        let mode: MCSessionSendDataMode = reliable ? .reliable : .unreliable
        let session = session
        // **Off the main thread — this is what jammed the lobby.** `MCSession.send`
        // is synchronous and can block while the transport does its work, and the
        // reliable send in `startRace` runs straight from a button action. Tapping
        // "Start race" wedged the main thread before the UI could redraw, so the
        // lobby froze with the button stuck and Back unresponsive. Reported from
        // device twice; the logic tests could never see it, because they replace
        // this call with nothing.
        //
        // Ordering still holds for reliable traffic: one serial queue, so the
        // roster and the start message cannot overtake each other.
        Self.sendQueue.async {
            // A failed send is not worth propagating: unreliable input is repaired
            // by the next packet's redundancy, and a reliable send failing means
            // the peer is gone, which arrives separately as a state change.
            try? session.send(data, toPeers: peers, with: mode)
        }
    }

    /// Serial, so reliable messages keep their order — a `RosterUpdate` overtaking
    /// the `RaceStart` that froze it would leave the peers disagreeing about who is
    /// racing.
    private static let sendQueue = DispatchQueue(label: "fi.misaki.skid.mc-send")
}

// MARK: - MCSessionDelegate

extension MultipeerTransport: MCSessionDelegate {
    public func session(
        _ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState
    ) {
        let name = peerID.displayName
        Task { @MainActor [weak self] in
            switch state {
            case .connected: self?.delegate?.transport(peerJoined: name)
            case .notConnected: self?.delegate?.transport(peerLeft: name)
            case .connecting: break
            @unknown default: break
            }
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let bytes = [UInt8](data)
        let name = peerID.displayName
        Task { @MainActor [weak self] in
            self?.delegate?.transport(didReceive: bytes, from: name)
        }
    }

    // Streams and resources are unused: the race sends small datagrams only.
    public func session(
        _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    public func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}

    public func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
    ) {}
}

// MARK: - Advertising and browsing

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    public func browser(
        _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        // **Invite only in one direction.** Both sides inviting each other creates
        // two sessions and MC resolves that by dropping one, which shows up as a
        // peer that connects and immediately disconnects. The guest browses and
        // invites; the host only advertises and accepts.
        let session = session
        Self.sendQueue.async {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

/// What to call this device, and — separately — how to tell it apart.
///
/// **A device name is not an identity.** Two iPhones are both called "iPhone"
/// unless their owners renamed them, and the roster is keyed by peer name: the
/// host was already seated as "iPhone", so the guest's join was refused as
/// `alreadyJoined` and silently dropped. Both screens then showed one device, both
/// believed they were the host, and Start stayed disabled. Reported from device.
///
/// So the key carries a short random suffix and the lobby shows only the part
/// before it. Both halves matter: a bare UUID would be unreadable in a lobby, and
/// a bare name is not unique.
public enum DeviceName {
    /// Separator between the friendly name and the uniquing suffix. `#` cannot
    /// appear in a device name a user typed, and survives MC's 63-byte limit.
    static let separator: Character = "#"

    /// The human part — what a player sees in someone else's lobby.
    public static var friendly: String {
        #if canImport(UIKit)
        let name = UIDevice.current.name
        #else
        let name = Host.current().localizedName ?? ""
        #endif
        return name.isEmpty ? "Skid player" : name
    }

    /// A unique key for this launch: the friendly name plus a random suffix.
    ///
    /// Uniqueness is per *launch*, not per install, which is the right scope: it
    /// only has to distinguish the devices in one race, and a value that survived
    /// a reinstall would be a device identifier — more than this needs.
    public static func uniqueKey(suffixLength: Int = 4) -> String {
        key(for: friendly, suffixLength: suffixLength)
    }

    /// The keying rule itself, with the name injected so a long one is testable.
    /// This machine's device name is short, so `uniqueKey()` alone can never
    /// exercise the length clamp — and a test that cannot reach a limit is not
    /// testing it.
    static func key(for name: String, suffixLength: Int = 4) -> String {
        let alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
        let suffix = String((0..<suffixLength).map { _ in alphabet.randomElement() ?? "x" })
        // Trimmed so name + separator + suffix stays inside MC's 63-byte limit;
        // MC truncates silently past it, which would chop the suffix off and
        // reintroduce the very collision this exists to prevent.
        let room = max(1, 60 - suffixLength - 1)
        return "\(name.prefix(room))\(separator)\(suffix)"
    }

    /// The friendly half of a peer key, for display. Falls back to the whole
    /// string, so a peer from a build without the suffix still shows sensibly.
    public static func display(_ peer: String) -> String {
        guard let index = peer.lastIndex(of: separator) else { return peer }
        let name = String(peer[peer.startIndex..<index])
        return name.isEmpty ? peer : name
    }
}
