import Foundation

/// The authoring model for a track: a closed polygon of corner nodes with
/// fillet radii, plus path-anchored gates and free-floating hazards. This is
/// what the track editor edits and what ships as JSON; `compile()` (see
/// TrackCompiler.swift) bakes it into the runtime `Track`. Design intent
/// lives here; baked geometry lives there — the sim never sees a design.
public struct TrackDesign: Equatable, Sendable, Codable {

    /// What kind of road the edge LEAVING a node is. Deck edges are the
    /// elevated bridge span (layer 1); ramps are the sloped approaches that
    /// carry the layer transition at the deck boundary.
    public enum EdgeKind: String, Equatable, Sendable, Codable {
        case ground
        case rampUp
        case deck
        case rampDown
    }

    /// One corner of the track polygon, in drive order.
    public struct Node: Equatable, Sendable, Codable {
        /// Stable id, assigned once and never reused within a design.
        /// Gate anchors reference nodes by id, so inserting or deleting
        /// OTHER nodes never silently re-targets a gate.
        public var id: Int
        public var position: Vec2
        /// Corner radius joining the adjacent edges; 0 = sharp corner.
        public var fillet: Double
        /// The edge leaving this node, toward the next node (the last
        /// node's edge closes the loop back to the first).
        public var edge: EdgeKind
        /// Red/white kerb striping on the OUTER side of this corner's
        /// fillet arc; everywhere else the ribbon keeps plain edges.
        /// Carried by the format for the renderer to adopt — selected
        /// corners get the classic stripes, by design not by default.
        public var kerb: Bool

        public init(
            id: Int, position: Vec2, fillet: Double = 0, edge: EdgeKind = .ground,
            kerb: Bool = false
        ) {
            self.id = id
            self.position = position
            self.fillet = fillet
            self.edge = edge
            self.kerb = kerb
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            position = try container.decode(Vec2.self, forKey: .position)
            fillet = try container.decodeIfPresent(Double.self, forKey: .fillet) ?? 0
            kerb = try container.decodeIfPresent(Bool.self, forKey: .kerb) ?? false
            edge = try container.decodeIfPresent(EdgeKind.self, forKey: .edge) ?? .ground
        }
    }

    /// How a gate line extends from its anchor point on the path.
    public enum GateSpan: Equatable, Sendable, Codable {
        /// The standard forgiving corridor gate: from `reach` past the
        /// ribbon's infield edge out to the boundary wall on the other
        /// side — running wide over grass still counts.
        case corridor(reach: Double)
        /// ±(width/2 − 2) across the ribbon, never wider than the bridge
        /// deck it sits on.
        case deck
        /// ±`half` around the anchor, for gates that want an exact span.
        case absolute(half: Double)
    }

    /// A gate anchored to the path: `t` ∈ [0, 1] along the edge leaving
    /// node `node` (by id). Gates are ordered in drive order; the LAST
    /// anchor is the start/finish line.
    public struct GateAnchor: Equatable, Sendable, Codable {
        public var node: Int
        public var t: Double
        public var span: GateSpan

        public init(node: Int, t: Double, span: GateSpan = .corridor(reach: 150)) {
            self.node = node
            self.t = t
            self.span = span
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            node = try container.decode(Int.self, forKey: .node)
            t = try container.decode(Double.self, forKey: .t)
            span =
                try container.decodeIfPresent(GateSpan.self, forKey: .span)
                ?? .corridor(reach: 150)
        }
    }

    /// Start-grid layout, derived from the start/finish gate: the pole sits
    /// `back` behind the line, slots follow every `gap` along the path,
    /// alternating `lateral` to either side (pole toward the infield).
    public struct StartGrid: Equatable, Sendable, Codable {
        public var back: Double
        public var gap: Double
        public var lateral: Double

        public init(back: Double = 70, gap: Double = 50, lateral: Double = 28) {
            self.back = back
            self.gap = gap
            self.lateral = lateral
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            back = try container.decodeIfPresent(Double.self, forKey: .back) ?? 70
            gap = try container.decodeIfPresent(Double.self, forKey: .gap) ?? 50
            lateral = try container.decodeIfPresent(Double.self, forKey: .lateral) ?? 28
        }
    }

    /// Stable identity (hiscores key — same as `Track.id`).
    public var id: String
    /// Display name for the picker.
    public var name: String
    /// Bumped when the geometry changes meaningfully — the future hook for
    /// telling records set on older geometry from current ones.
    public var revision: Int
    /// Visual theme for the whole map ("grass" today; "sand", "snow" …
    /// later). Carried by the format; the renderer adopts it when themes
    /// land.
    public var theme: String
    /// World bounds.
    public var size: Vec2
    /// Full width of the asphalt ribbon.
    public var width: Double
    /// The closed corner polygon, in drive order (≥ 3 nodes).
    public var nodes: [Node]
    /// Ordered checkpoint anchors; the last one is the start/finish line.
    public var gates: [GateAnchor]
    /// Free-floating hazards, in world coordinates (pass through unbaked).
    public var hazards: [SurfacePatch]
    public var grid: StartGrid
    /// Authored pause-button anchor: an infield spot clear of the racing
    /// line. Optional; validated off-ribbon when present.
    public var pit: Vec2?
    /// Extra walls beyond the derived boundary + ramp retaining walls.
    public var extraWalls: [Wall]

    public init(
        id: String,
        name: String,
        revision: Int = 1,
        theme: String = "grass",
        size: Vec2,
        width: Double,
        nodes: [Node],
        gates: [GateAnchor],
        hazards: [SurfacePatch] = [],
        grid: StartGrid = StartGrid(),
        pit: Vec2? = nil,
        extraWalls: [Wall] = []
    ) {
        self.id = id
        self.name = name
        self.revision = revision
        self.theme = theme
        self.size = size
        self.width = width
        self.nodes = nodes
        self.gates = gates
        self.hazards = hazards
        self.grid = grid
        self.pit = pit
        self.extraWalls = extraWalls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "grass"
        size = try container.decode(Vec2.self, forKey: .size)
        width = try container.decode(Double.self, forKey: .width)
        nodes = try container.decode([Node].self, forKey: .nodes)
        gates = try container.decode([GateAnchor].self, forKey: .gates)
        hazards = try container.decodeIfPresent([SurfacePatch].self, forKey: .hazards) ?? []
        grid = try container.decodeIfPresent(StartGrid.self, forKey: .grid) ?? StartGrid()
        pit = try container.decodeIfPresent(Vec2.self, forKey: .pit)
        extraWalls = try container.decodeIfPresent([Wall].self, forKey: .extraWalls) ?? []
    }
}
