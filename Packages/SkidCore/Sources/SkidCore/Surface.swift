/// What the car is driving on. Surfaces are simulation data, not decoration:
/// each maps to grip/drag/traction modifiers the step function applies.
/// Exact values are feel-tuning.
public enum Surface: Equatable, Sendable, Codable, CaseIterable {
    case asphalt
    case grass
    case mud
    case water
    case oil

    /// How fast lateral (sliding) velocity decays, 1/s. Lower = slipperier.
    /// The steady-state drift angle in a full-lock corner is roughly
    /// turnRate/grip — asphalt at 7 vs. a 3.4 turn rate holds a visible but
    /// controllable slide.
    public var grip: Double {
        switch self {
        case .asphalt: return 7.0
        case .grass: return 2.2
        case .mud: return 4.0
        case .water: return 1.4
        case .oil: return 0.35
        }
    }

    /// Passive speed loss, 1/s (includes rolling resistance).
    public var drag: Double {
        switch self {
        case .asphalt: return 0.35
        case .grass: return 1.7
        case .mud: return 3.6
        case .water: return 2.8
        case .oil: return 0.05
        }
    }

    /// How much of engine/brake force reaches the ground, 0…1.
    public var traction: Double {
        switch self {
        case .asphalt: return 1.0
        case .grass: return 0.55
        case .mud: return 0.4
        case .water: return 0.5
        case .oil: return 0.1
        }
    }
}
