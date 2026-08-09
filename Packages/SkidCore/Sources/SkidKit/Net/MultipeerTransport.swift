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
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    /// Guest: look for a host and invite ourselves in.
    public func startBrowsing() {
        stopDiscovery()
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    /// Stop looking, but stay connected — called once the race starts, so a
    /// latecomer cannot join mid-race and discovery stops costing radio.
    public func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    public func disconnect() {
        stopDiscovery()
        session.disconnect()
    }

    // MARK: - Sending

    public func send(_ bytes: [UInt8], reliable: Bool) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        // A failed send is not worth propagating: unreliable input is repaired by
        // the next packet's redundancy, and a reliable send failing means the peer
        // is gone, which arrives separately as a state change.
        try? session.send(
            Data(bytes), toPeers: peers, with: reliable ? .reliable : .unreliable)
    }
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
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
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
