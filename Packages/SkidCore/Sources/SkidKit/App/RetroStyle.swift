import SwiftUI

/// **The menus' look: a 90s PC game, with 2020s manners.**
///
/// The racing is top-down arcade, and native iOS chrome around it reads like a settings
/// app that happens to contain a game. This is the other direction — hard edges, a
/// saturated VGA palette, beveled panels, monospaced type.
///
/// **The retro is in the paint, not in the interaction.** A period-accurate DOS menu
/// wants arrow keys, a blinking cursor and 8px hit targets; none of that survives a
/// thumb. So: real buttons at real sizes, native scrolling, native switches underneath
/// the paint, and no affectation that costs usability. The look is 1994; the ergonomics
/// are not.
enum Retro {
    // MARK: - Palette
    //
    // Chosen against the game's own grass green so the menus and the track look like one
    // product. Deliberately few: a 90s palette's charm is partly that it had to be.

    /// Panel face — the mid grey of every DOS dialog.
    static let panel = Color(red: 0.66, green: 0.66, blue: 0.62)
    /// The recessed area a panel sits on.
    static let ground = Color(red: 0.16, green: 0.20, blue: 0.28)
    /// Bevel highlight: up and to the left, as if lit from there.
    static let bevelLight = Color(red: 0.88, green: 0.88, blue: 0.84)
    /// Bevel shadow: down and to the right.
    static let bevelDark = Color(red: 0.32, green: 0.32, blue: 0.30)
    /// Ink on a panel.
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.12)
    /// Muted ink, for secondary rows.
    static let inkSoft = Color(red: 0.34, green: 0.34, blue: 0.36)
    /// The title bar and selection colour — VGA blue.
    static let highlight = Color(red: 0.12, green: 0.18, blue: 0.55)
    /// Text on `highlight`.
    static let onHighlight = Color(red: 0.96, green: 0.96, blue: 0.90)
    /// Warning/destructive.
    static let danger = Color(red: 0.65, green: 0.10, blue: 0.10)
    /// The accent used for values and emphasis — amber, like a monochrome terminal.
    static let amber = Color(red: 0.94, green: 0.72, blue: 0.16)
    /// **Text directly on `ground`**, rather than on a panel.
    ///
    /// A distinct token because `ink` is dark-on-grey and unreadable out here: section
    /// headings that sit between panels went nearly invisible against the dark ground
    /// until this existed. On a panel use `ink`/`inkSoft`; off one, use these.
    static let onGround = Color(red: 0.90, green: 0.90, blue: 0.86)
    /// Secondary text on `ground`.
    static let onGroundSoft = Color(red: 0.62, green: 0.66, blue: 0.72)

    // MARK: - Type

    /// The menu face. Monospaced by design — it is what a DOS menu looked like, and it
    /// keeps value columns aligned for free.
    static func font(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// A screen title, in the chunky style of a game's own logo rather than a nav bar.
    static var title: Font { font(22, weight: .black) }
    /// A section heading inside a panel.
    static var heading: Font { font(12, weight: .bold) }
    /// A row label.
    static var body: Font { font(15, weight: .bold) }
    /// Fine print.
    static var caption: Font { font(11, weight: .regular) }
}

// MARK: - The bevel

/// A hard-edged panel with a two-tone bevel: light from the top-left, dark to the
/// bottom-right (or inverted, for a *pressed* or recessed look).
///
/// Drawn as four strokes rather than a gradient, because the whole point is that the
/// transition is abrupt — a gradient would read as a soft modern card wearing retro
/// colours.
struct RetroBevel: View {
    var inset = false
    var thickness: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let light = inset ? Retro.bevelDark : Retro.bevelLight
            let dark = inset ? Retro.bevelLight : Retro.bevelDark
            Path { path in
                path.addRect(CGRect(x: 0, y: 0, width: width, height: thickness))
                path.addRect(CGRect(x: 0, y: 0, width: thickness, height: height))
            }
            .fill(light)
            Path { path in
                path.addRect(
                    CGRect(
                        x: 0, y: height - thickness, width: width, height: thickness))
                path.addRect(
                    CGRect(
                        x: width - thickness, y: 0, width: thickness, height: height))
            }
            .fill(dark)
        }
        .allowsHitTesting(false)
    }
}

/// **A screen's title — and deliberately not a button.**
///
/// The first version was a beveled blue bar, which read as something to press; making
/// the bevel inset only made it read as a *pressed* button. The bevel was the problem.
/// A title is now flat colour with checkered rules under it: nothing in the app's button
/// vocabulary, so there is nothing to mistake.
struct RetroTitle: View {
    private let label: Text

    init(_ label: Text) {
        self.label = label
    }

    var body: some View {
        VStack(spacing: 8) {
            label
                .font(Retro.font(20, weight: .black))
                .foregroundStyle(Retro.amber)
                .frame(maxWidth: .infinity)
            RetroCheckers(rows: 2, cell: 6)
        }
    }
}

/// A section heading inside a panel. Flat, uppercase, never interactive.
struct RetroHeading: View {
    private let label: Text

    init(_ label: Text) {
        self.label = label
    }

    var body: some View {
        label
            .font(Retro.heading)
            .foregroundStyle(Retro.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// **A checkered block, drawn as square pixels.**
///
/// The cheap, cheerful racing-game decoration — a start/finish flag rendered the way a
/// 90s title screen would have: no waves, no cloth, no gradient, just alternating squares
/// on a grid. `rows` deep and as many columns as fit, so it tiles to whatever width it is
/// given.
struct RetroCheckers: View {
    var rows = 3
    var cell: CGFloat = 8
    var light = Color(red: 0.94, green: 0.94, blue: 0.90)
    var dark = Color(red: 0.10, green: 0.10, blue: 0.12)

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / cell))
            for row in 0..<rows {
                for column in 0..<columns {
                    guard (row + column).isMultiple(of: 2) else { continue }
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                width: cell, height: cell)),
                        with: .color(light))
                }
            }
        }
        .background(dark)
        .frame(height: CGFloat(rows) * cell)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Raised panel: the surface every menu is built on.
    func retroPanel(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Retro.panel)
            .overlay(RetroBevel())
    }

    /// A pressed/recessed well — for value fields and list backgrounds.
    func retroWell(padding: CGFloat = 10) -> some View {
        self
            .padding(padding)
            .background(Retro.panel.opacity(0.55))
            .overlay(RetroBevel(inset: true, thickness: 2))
    }

    /// The standard menu button: square, beveled, and finger-sized.
    ///
    /// `wide` fills the available width, for a stacked menu; otherwise it hugs, for a
    /// footer row. Minimum height is 44 either way — the one number here that is modern
    /// rather than period, and deliberately so.
    func retroButton(wide: Bool = false, tint: Color = Retro.panel) -> some View {
        self
            .font(Retro.body)
            .foregroundStyle(tint == Retro.panel ? Retro.ink : Retro.onHighlight)
            .padding(.horizontal, 18)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 44)
            .background(tint)
            .overlay(RetroBevel())
    }
}

/// A labelled on/off row.
///
/// Drawn rather than a `Toggle`, so it matches the panel — but it is a plain button with
/// a 44pt row, so it behaves like every other control here. The state reads as a word
/// (`ON` / `OFF`) as well as a colour, which a switch does not.
struct RetroToggle: View {
    let label: Text
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                label
                    .font(Retro.body)
                    .foregroundStyle(Retro.ink)
                Spacer(minLength: 12)
                Text(isOn ? "ON" : "OFF", bundle: .module)
                    .font(Retro.body)
                    .foregroundStyle(isOn ? Retro.onHighlight : Retro.inkSoft)
                    .frame(width: 56, height: 30)
                    .background(isOn ? Retro.highlight : Retro.panel.opacity(0.5))
                    .overlay(RetroBevel(inset: !isOn, thickness: 2))
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// One option in a pick-one list, marked by a DOS-style ▸ rather than a checkmark.
struct RetroChoice: View {
    let label: Text
    var detail: Text?
    let selected: Bool
    /// An optional colour chip — a player's car colour, drawn as a square pixel.
    var swatch: Color?
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: 8) {
                Text(verbatim: selected ? "▸" : " ")
                    .font(Retro.body)
                    .foregroundStyle(Retro.amber)
                if let swatch {
                    Rectangle()
                        .fill(swatch)
                        .frame(width: 18, height: 18)
                        .overlay(RetroBevel(thickness: 2))
                }
                VStack(alignment: .leading, spacing: 2) {
                    label
                        .font(Retro.body)
                    if let detail {
                        detail
                            .font(Retro.caption)
                            .foregroundStyle(
                                selected ? Retro.onHighlight.opacity(0.8) : Retro.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Retro.onHighlight : Retro.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Retro.highlight : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
