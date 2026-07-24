import Foundation

/// An **exact** 1-D coordinate for the piece model: the value `(a + b·√2) / 2`
/// with integer `a`, `b`. This ring is closed under addition and under the
/// entries of a 45° rotation (0, ±1, ±√2⁄2 = ±(0 + 1·√2)/2), so straights of
/// integer length and arcs of integer radius, walked at any of the 8 headings,
/// always land on values of this form. Equality is therefore **exact integer
/// comparison** — the whole point: loop closure and port mating need no
/// epsilon, and a shared track code decodes bit-identically everywhere. Floats
/// appear only when a finished layout is lowered to `Vec2` at compile time.
public struct Coord: Equatable, Hashable, Sendable, Codable {
    /// Value = (a + b·√2) / 2.
    public var a: Int
    public var b: Int

    public init(a: Int, b: Int) {
        self.a = a
        self.b = b
    }

    public static let zero = Coord(a: 0, b: 0)

    /// An exact integer (2n / 2).
    public init(_ n: Int) {
        self.init(a: 2 * n, b: 0)
    }

    public static func + (x: Coord, y: Coord) -> Coord {
        Coord(a: x.a + y.a, b: x.b + y.b)
    }

    public static func - (x: Coord, y: Coord) -> Coord {
        Coord(a: x.a - y.a, b: x.b - y.b)
    }

    public static prefix func - (x: Coord) -> Coord {
        Coord(a: -x.a, b: -x.b)
    }

    /// Scale by an integer — stays exact.
    public static func * (x: Coord, n: Int) -> Coord {
        Coord(a: x.a * n, b: x.b * n)
    }

    /// The real value, for lowering to `Vec2` at compile time only.
    public var value: Double {
        (Double(a) + Double(b) * 2.0.squareRoot()) / 2
    }
}

/// An exact 2-D point in the piece model — a `Coord` pair.
public struct CoordPoint: Equatable, Hashable, Sendable, Codable {
    public var x: Coord
    public var y: Coord

    public init(x: Coord, y: Coord) {
        self.x = x
        self.y = y
    }

    public static let zero = CoordPoint(x: .zero, y: .zero)

    /// Exact integer point (whole units on both axes).
    public init(_ ix: Int, _ iy: Int) {
        self.init(x: Coord(ix), y: Coord(iy))
    }

    public static func + (p: CoordPoint, q: CoordPoint) -> CoordPoint {
        CoordPoint(x: p.x + q.x, y: p.y + q.y)
    }

    public static func - (p: CoordPoint, q: CoordPoint) -> CoordPoint {
        CoordPoint(x: p.x - q.x, y: p.y - q.y)
    }

    public static func += (p: inout CoordPoint, q: CoordPoint) { p = p + q }

    /// Scale both axes by an integer — stays exact.
    public static func * (p: CoordPoint, n: Int) -> CoordPoint {
        CoordPoint(x: p.x * n, y: p.y * n)
    }

    /// Lower to the sim's float geometry — the one lossy step, at compile time.
    public var vec2: Vec2 {
        Vec2(x.value, y.value)
    }
}

/// A heading quantized to the 8 compass directions, 0 = +x, counting
/// counterclockwise in 45° steps (0=E, 1=NE, 2=N, … 7=SE). All piece geometry
/// is expressed against these, so diagonals are first-class, never grid
/// approximations.
public struct Heading: Equatable, Hashable, Sendable, Codable {
    /// 0…7.
    public var step: Int

    public init(_ step: Int) {
        self.step = ((step % 8) + 8) % 8
    }

    public static let east = Heading(0)

    /// Turn left (counterclockwise) by `eighths` 45° steps.
    public func turnedLeft(_ eighths: Int = 1) -> Heading { Heading(step + eighths) }
    /// Turn right (clockwise) by `eighths` 45° steps.
    public func turnedRight(_ eighths: Int = 1) -> Heading { Heading(step - eighths) }
    /// The opposite heading.
    public var reversed: Heading { Heading(step + 4) }

    /// The exact unit step for a length-1 move along this heading. Cardinals
    /// are (±1, 0)/(0, ±1); diagonals are (±√2⁄2, ±√2⁄2), i.e. `Coord(a:0,b:1)`
    /// per axis — all inside the ring, so a straight of integer length lands
    /// exactly.
    public var unitStep: CoordPoint {
        // diagonal component √2⁄2 = (0 + 1·√2)/2 → Coord(a: 0, b: 1)
        let d = Coord(a: 0, b: 1)
        let one = Coord(1)
        switch step {
        case 0: return CoordPoint(x: one, y: .zero)  // E
        case 1: return CoordPoint(x: d, y: d)  // NE
        case 2: return CoordPoint(x: .zero, y: one)  // N
        case 3: return CoordPoint(x: -d, y: d)  // NW
        case 4: return CoordPoint(x: -one, y: .zero)  // W
        case 5: return CoordPoint(x: -d, y: -d)  // SW
        case 6: return CoordPoint(x: .zero, y: -one)  // S
        default: return CoordPoint(x: d, y: -d)  // SE
        }
    }

    /// Radians, for lowering at compile time.
    public var radians: Double { Double(step) * .pi / 4 }
}

/// A pose in the piece model: an exact position plus a quantized heading. The
/// walk threads poses through pieces; a port is a pose (position + heading the
/// road faces there).
public struct PiecePose: Equatable, Hashable, Sendable, Codable {
    public var position: CoordPoint
    public var heading: Heading

    public init(position: CoordPoint, heading: Heading) {
        self.position = position
        self.heading = heading
    }

    public static let origin = PiecePose(position: .zero, heading: .east)

    /// Advance straight by an integer length along the current heading.
    public func advanced(by length: Int) -> PiecePose {
        PiecePose(position: position + heading.unitStep * length, heading: heading)
    }
}
