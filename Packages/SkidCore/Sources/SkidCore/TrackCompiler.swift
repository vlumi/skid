import Foundation

/// Everything that can be wrong with a design, typed so the editor can
/// point at the offending node/gate instead of printing a stack trace.
public enum TrackDesignError: Error, Equatable, Sendable {
    case tooFewNodes(count: Int)
    case duplicateNodeID(Int)
    case nonPositiveWidth
    /// Two consecutive nodes share a position.
    case degenerateEdge(node: Int)
    /// A ~180° turn cannot be filleted by one node — split the hairpin
    /// into two nodes with a short cross edge between them.
    case degenerateTurn(node: Int)
    /// The fillets at an edge's two ends need more length than it has.
    case filletOverflow(edgeFromNode: Int, needed: Double, available: Double)
    /// Deck boundaries carry the layer transition; the node must be sharp.
    case filletAtLayerTransition(node: Int)
    /// Every deck run must be entered over a rampUp and left over a
    /// rampDown (and ramps must connect to a deck).
    case deckNotBracketed(node: Int)
    case noGates
    case unknownGateNode(gateIndex: Int, node: Int)
    /// The anchor lands inside a trimmed corner, where the edge tangent
    /// no longer matches the path.
    case gateInsideFillet(gateIndex: Int)
    /// A `.deck` span only makes sense on a deck edge.
    case deckSpanOffDeck(gateIndex: Int)
    case startSlotOffRibbon(slot: Int)
    case pitOnRibbon
}

extension TrackDesign {
    /// Bake the design into the runtime `Track`. Pure and deterministic:
    /// the same design always compiles to the identical track, bit for bit.
    public func compile() throws -> Track {
        if let issue = structuralIssues().first { throw issue }
        let corners = try filletedCorners()
        let (points, owners) = polyline(corners: corners)
        let gates = try compiledGates(corners: corners)
        let (slots, heading) = startGrid(anchor: self.gates[self.gates.count - 1])
        let track = Track(
            id: id,
            centerline: points,
            width: width,
            elevatedSegments: Set(owners.indices.filter { kind(ofEdge: owners[$0]) == .deck }),
            rampSegments: Set(
                owners.indices.filter {
                    let kind = kind(ofEdge: owners[$0])
                    return kind == .rampUp || kind == .rampDown
                }),
            ramps: transitionRamps(),
            walls: boundaryWalls() + rampRetainingWalls(corners: corners) + extraWalls,
            gates: gates,
            patches: hazards,
            startSlots: slots,
            startHeading: heading,
            size: size
        )
        for (index, slot) in track.startSlots.enumerated()
        where track.surface(at: slot) != .asphalt {
            throw TrackDesignError.startSlotOffRibbon(slot: index)
        }
        if let pit, track.distanceToCenterline(pit) <= width / 2 + 20 {
            throw TrackDesignError.pitOnRibbon
        }
        return track
    }

    /// Every problem at once, for the editor's issue panel (`compile()`
    /// throws the first of these).
    public func validationIssues() -> [TrackDesignError] {
        var issues = structuralIssues()
        guard issues.isEmpty else { return issues }
        do {
            _ = try compile()
        } catch let error as TrackDesignError {
            issues.append(error)
        } catch {
            // compile() only throws TrackDesignError.
        }
        return issues
    }

    // MARK: - Structural validation

    private func structuralIssues() -> [TrackDesignError] {
        var issues: [TrackDesignError] = []
        if nodes.count < 3 { issues.append(.tooFewNodes(count: nodes.count)) }
        var seen = Set<Int>()
        for node in nodes where !seen.insert(node.id).inserted {
            issues.append(.duplicateNodeID(node.id))
        }
        if width <= 0 { issues.append(.nonPositiveWidth) }
        for i in nodes.indices where nodes[i].position == next(of: i).position {
            issues.append(.degenerateEdge(node: nodes[i].id))
        }
        issues += layerIssues()
        if gates.isEmpty { issues.append(.noGates) }
        for (gateIndex, anchor) in gates.enumerated() {
            if nodeIndex(id: anchor.node) == nil {
                issues.append(.unknownGateNode(gateIndex: gateIndex, node: anchor.node))
            } else if case .deck = anchor.span,
                kind(ofEdge: nodeIndex(id: anchor.node)!) != .deck
            {
                issues.append(.deckSpanOffDeck(gateIndex: gateIndex))
            }
        }
        return issues
    }

    /// Layer rules at every node (the junction of edge i−1 and edge i):
    /// deck runs bracketed by ramps, and deck boundaries sharp.
    private func layerIssues() -> [TrackDesignError] {
        var issues: [TrackDesignError] = []
        for i in nodes.indices {
            let incoming = kind(ofEdge: (i + nodes.count - 1) % nodes.count)
            let outgoing = kind(ofEdge: i)
            let id = nodes[i].id
            switch (incoming, outgoing) {
            case (.rampUp, .deck), (.deck, .rampDown):
                if nodes[i].fillet != 0 {
                    issues.append(.filletAtLayerTransition(node: id))
                }
            case (.deck, .deck):
                break  // mid-span deck node — fine, may even curve
            case (.rampUp, _), (_, .rampDown), (.deck, _), (_, .deck):
                // Any other pairing involving a deck or the deck side of a
                // ramp breaks the rampUp → deck → rampDown bracket.
                issues.append(.deckNotBracketed(node: id))
            default:
                break
            }
        }
        return issues
    }

    // MARK: - Fillets

    /// A node's baked corner: the arc points (a single point when sharp)
    /// plus how much the fillet trims off the adjacent edges.
    struct Corner {
        var points: [Vec2]
        var trimIn: Double
        var trimOut: Double
    }

    /// Max direction change per baked arc segment (6°): the smoothness of
    /// every curve on every track. Integer step counts keep it exact.
    private static let maxArcStep = Double.pi / 30

    func filletedCorners() throws -> [Corner] {
        var corners: [Corner] = []
        for i in nodes.indices {
            corners.append(try corner(at: i))
        }
        // Fillets at an edge's two ends must fit inside it.
        for i in nodes.indices {
            let length = (next(of: i).position - nodes[i].position).length
            let needed = corners[i].trimOut + corners[(i + 1) % nodes.count].trimIn
            if needed > length - 0.001 {
                throw TrackDesignError.filletOverflow(
                    edgeFromNode: nodes[i].id, needed: needed, available: length)
            }
        }
        return corners
    }

    private func corner(at i: Int) throws -> Corner {
        let previous = nodes[(i + nodes.count - 1) % nodes.count].position
        let current = nodes[i].position
        let following = next(of: i).position
        let inbound = (current - previous).normalized
        let outbound = (following - current).normalized
        let turn = atan2(inbound.cross(outbound), inbound.dot(outbound))
        guard nodes[i].fillet > 0, abs(turn) > 1e-9 else {
            return Corner(points: [current], trimIn: 0, trimOut: 0)
        }
        guard .pi - abs(turn) > 1e-6 else {
            throw TrackDesignError.degenerateTurn(node: nodes[i].id)
        }
        let radius = nodes[i].fillet
        let trim = radius * tan(abs(turn) / 2)
        let entry = current - inbound * trim
        let inward = inbound.perpendicular * (turn > 0 ? 1 : -1)
        let center = entry + inward * radius
        let startAngle = atan2(entry.y - center.y, entry.x - center.x)
        let steps = max(1, Int((abs(turn) / Self.maxArcStep).rounded(.up)))
        let points = (0...steps).map { step in
            center + Vec2(angle: startAngle + turn * Double(step) / Double(steps)) * radius
        }
        return Corner(points: points, trimIn: trim, trimOut: trim)
    }

    // MARK: - Polyline emission

    /// The baked centerline plus, per segment, the design edge it came
    /// from. Arc segments belong to the edge LEAVING their node — so a
    /// sharp deck boundary is exactly where deck segments start/stop.
    func polyline(corners: [Corner]) -> (points: [Vec2], owners: [Int]) {
        var points: [Vec2] = []
        var owners: [Int] = []
        for i in nodes.indices {
            for (offset, point) in corners[i].points.enumerated() {
                if offset > 0 { owners.append(i) }
                points.append(point)
            }
            // The straight from this corner's exit to the next corner's
            // entry (for the last node: the closing segment to points[0]).
            owners.append(i)
        }
        return (points, owners)
    }

    // MARK: - Layers

    /// Layer-transition lines at the deck boundaries, spanning slightly
    /// narrower than the deck so a crossing always lands inside the
    /// fall-off tolerance.
    private func transitionRamps() -> [Ramp] {
        var ramps: [Ramp] = []
        let half = width / 2 - 2
        for i in nodes.indices {
            let incoming = kind(ofEdge: (i + nodes.count - 1) % nodes.count)
            let outgoing = kind(ofEdge: i)
            let position = nodes[i].position
            if incoming == .rampUp, outgoing == .deck {
                let deckDirection = (next(of: i).position - position).normalized
                let across = deckDirection.perpendicular * half
                ramps.append(
                    Ramp(
                        from: position - across, to: position + across,
                        forward: deckDirection))
            }
            if incoming == .deck, outgoing == .rampDown {
                let previous = nodes[(i + nodes.count - 1) % nodes.count].position
                let deckDirection = (position - previous).normalized
                let across = deckDirection.perpendicular * half
                ramps.append(
                    Ramp(
                        from: position - across, to: position + across,
                        forward: deckDirection, fromLayer: 1, toLayer: 0))
            }
        }
        return ramps
    }

    /// Retaining walls along each ramp edge's sides: a ramp is entered
    /// from the road below or the deck above, never sideways.
    private func rampRetainingWalls(corners: [Corner]) -> [Wall] {
        var walls: [Wall] = []
        for i in nodes.indices {
            let kind = kind(ofEdge: i)
            guard kind == .rampUp || kind == .rampDown else { continue }
            let start = corners[i].points[corners[i].points.count - 1]
            let end = corners[(i + 1) % nodes.count].points[0]
            let (ground, deck) = kind == .rampUp ? (start, end) : (end, start)
            let side = (deck - ground).normalized.perpendicular
            for sign in [-1.0, 1.0] {
                walls.append(
                    Wall(
                        from: ground + side * (width / 2 * sign),
                        to: deck + side * ((width / 2 + 8) * sign)))
            }
        }
        return walls
    }

    // MARK: - Gates

    private func compiledGates(corners: [Corner]) throws -> [Gate] {
        var compiled: [Gate] = []
        for (gateIndex, anchor) in gates.enumerated() {
            compiled.append(
                try compiledGate(anchor, index: gateIndex, corners: corners))
        }
        return compiled
    }

    private func compiledGate(
        _ anchor: GateAnchor, index: Int, corners: [Corner]
    ) throws -> Gate {
        guard let i = nodeIndex(id: anchor.node) else {
            throw TrackDesignError.unknownGateNode(gateIndex: index, node: anchor.node)
        }
        let start = nodes[i].position
        let edge = next(of: i).position - start
        let along = anchor.t * edge.length
        // The anchor must sit on the retained straight, where the edge
        // direction is the true path tangent.
        let nextTrim = corners[(i + 1) % nodes.count].trimIn
        guard along >= corners[i].trimOut - 0.001, along <= edge.length - nextTrim + 0.001
        else {
            throw TrackDesignError.gateInsideFillet(gateIndex: index)
        }
        let direction = edge.normalized
        let anchorPoint = start + direction * along
        let layer = kind(ofEdge: i) == .deck ? 1 : 0
        switch anchor.span {
        case .corridor(let reach):
            let inward = infieldNormal(of: direction)
            let inner = anchorPoint + inward * (width / 2 + reach)
            let outer = raycastToBoundary(from: anchorPoint, along: inward * -1)
            return Gate(from: inner, to: outer, forward: direction, layer: layer)
        case .deck:
            let across = direction.perpendicular * (width / 2 - 2)
            return Gate(
                from: anchorPoint - across, to: anchorPoint + across,
                forward: direction, layer: layer)
        case .absolute(let half):
            let across = direction.perpendicular * half
            return Gate(
                from: anchorPoint - across, to: anchorPoint + across,
                forward: direction, layer: layer)
        }
    }

    // MARK: - Start grid

    /// Grid slots behind the start/finish anchor, pole toward the infield,
    /// all facing the drive direction.
    private func startGrid(anchor: GateAnchor) -> (slots: [Vec2], heading: Double) {
        guard let i = nodeIndex(id: anchor.node) else { return ([], 0) }
        let start = nodes[i].position
        let edge = next(of: i).position - start
        let direction = edge.normalized
        let line = start + direction * (anchor.t * edge.length)
        let inward = infieldNormal(of: direction)
        let slots = (0..<4).map { slot in
            line - direction * (grid.back + Double(slot) * grid.gap)
                + inward * (slot % 2 == 0 ? grid.lateral : -grid.lateral)
        }
        return (slots, atan2(direction.y, direction.x))
    }

    // MARK: - Geometry helpers

    private func next(of i: Int) -> Node { nodes[(i + 1) % nodes.count] }

    private func nodeIndex(id: Int) -> Int? { nodes.firstIndex { $0.id == id } }

    private func kind(ofEdge i: Int) -> EdgeKind { nodes[i].edge }

    /// The polygon's signed area decides which perpendicular points at the
    /// infield: interior is left of travel on a counterclockwise loop.
    private var windingSign: Double {
        var doubledArea = 0.0
        for i in nodes.indices {
            doubledArea += nodes[i].position.cross(next(of: i).position)
        }
        return doubledArea > 0 ? 1 : -1
    }

    private func infieldNormal(of direction: Vec2) -> Vec2 {
        direction.perpendicular * windingSign
    }

    /// Where a ray from `point` exits the playfield's wall rectangle
    /// (inset 8 from the world edge, matching the boundary walls).
    private func raycastToBoundary(from point: Vec2, along direction: Vec2) -> Vec2 {
        let inset = 8.0
        var travel = Double.greatestFiniteMagnitude
        if direction.x != 0 {
            let target = direction.x > 0 ? size.x - inset : inset
            travel = min(travel, (target - point.x) / direction.x)
        }
        if direction.y != 0 {
            let target = direction.y > 0 ? size.y - inset : inset
            travel = min(travel, (target - point.y) / direction.y)
        }
        return point + direction * travel
    }

    /// Playfield boundary walls, inset from the world edge.
    private func boundaryWalls() -> [Wall] {
        let inset = 8.0
        let bounds = [
            Vec2(inset, inset), Vec2(size.x - inset, inset),
            Vec2(size.x - inset, size.y - inset), Vec2(inset, size.y - inset),
        ]
        return bounds.indices.map { i in
            Wall(from: bounds[i], to: bounds[(i + 1) % bounds.count])
        }
    }
}
