import SkidCore
import SwiftUI

/// One button the keyboard can reach: where it sits on screen and what it does.
/// A reference, so a button can refresh its action every render without the
/// scope having to re-register it.
@MainActor
final class MenuTarget: ObservableObject {
    var action: () -> Void = {}
    /// The surface's way OUT (its corner ‹ or ×): Escape presses it.
    var isCancel = false
    var frame: CGRect = .zero
}

/// **The buttons of one surface** — a screen, or a sheet over it — and which
/// of them the keyboard highlight is on.
@MainActor
public final class MenuFocusScope: ObservableObject {
    @Published private(set) var focused: MenuTarget?
    private(set) var targets: [MenuTarget] = []

    public init() {}

    func register(_ target: MenuTarget) {
        guard !targets.contains(where: { $0 === target }) else { return }
        targets.append(target)
    }

    func unregister(_ target: MenuTarget) {
        targets.removeAll { $0 === target }
        if focused === target { focused = nil }
    }

    /// An arrow: the highlight moves to the best button that way (see
    /// `SpatialFocus`), or appears on the first one if it was nowhere.
    func move(_ direction: FocusDirection) {
        let frames = targets.map(\.frame.asRect)
        let current = focused.flatMap { f in targets.firstIndex { $0 === f } }.map { frames[$0] }
        if let index = SpatialFocus.next(from: current, among: frames, direction: direction) {
            focused = targets[index]
        }
    }

    /// Enter or Space: press the highlighted button — or, with nothing
    /// highlighted yet, show where the highlight is first.
    func activate() {
        guard let focused else { return move(.down) }
        focused.action()
    }

    /// Escape: press this surface's way out, if it has one.
    func cancel() {
        targets.last(where: \.isCancel)?.action()
    }
}

/// **Which surface the keys drive**: the most recently shown. A sheet pushes
/// its scope over the screen's, so arrows move inside the sheet, and the
/// screen gets them back when the sheet goes.
@MainActor
public final class MenuFocusCenter {
    private var stack: [MenuFocusScope] = []

    public init() {}

    public var active: MenuFocusScope? { stack.last }

    func push(_ scope: MenuFocusScope) {
        stack.removeAll { $0 === scope }
        stack.append(scope)
    }

    func pop(_ scope: MenuFocusScope) {
        stack.removeAll { $0 === scope }
    }
}

private struct MenuScopeKey: EnvironmentKey {
    static let defaultValue: MenuFocusScope? = nil
}

private struct MenuCenterKey: EnvironmentKey {
    static let defaultValue: MenuFocusCenter? = nil
}

extension EnvironmentValues {
    var menuScope: MenuFocusScope? {
        get { self[MenuScopeKey.self] }
        set { self[MenuScopeKey.self] = newValue }
    }

    var menuFocusCenter: MenuFocusCenter? {
        get { self[MenuCenterKey.self] }
        set { self[MenuCenterKey.self] = newValue }
    }
}

extension View {
    /// The game's focus centre, once, at the root.
    func menuFocusCenter(_ center: MenuFocusCenter) -> some View {
        environment(\.menuFocusCenter, center)
    }

    /// A surface with its own keyboard focus: a screen, or a sheet over one.
    func menuFocusScope() -> some View {
        modifier(MenuScopeModifier())
    }
}

private struct MenuScopeModifier: ViewModifier {
    @Environment(\.menuFocusCenter) private var center
    @StateObject private var scope = MenuFocusScope()

    func body(content: Content) -> some View {
        content
            .environment(\.menuScope, scope)
            .onAppear { center?.push(scope) }
            .onDisappear { center?.pop(scope) }
    }
}

/// **A button the keyboard can reach** — a plain `Button` that also tells its
/// surface where it is, and wears the highlight when the arrows land on it.
/// On a touch device nothing ever focuses it, so it is just a `Button`.
struct MenuButton<Label: View>: View {
    private let action: () -> Void
    private let isCancel: Bool
    private let label: Label
    @Environment(\.menuScope) private var scope
    @StateObject private var target = MenuTarget()

    init(cancel: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.isCancel = cancel
        self.label = label()
    }

    var body: some View {
        // The latest closure, every render — a row's action captures its row.
        // swiftlint:disable:next redundant_discardable_let
        let _ = refresh()
        Button(action: action) { label }
            // Where the button is, kept current as it moves (a scroll, a
            // resize) — the frame the arrows navigate by.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                target.frame = $0
            }
            .onAppear { scope?.register(target) }
            .onDisappear { scope?.unregister(target) }
            .overlay {
                if let scope { FocusRing(scope: scope, target: target) }
            }
    }

    private func refresh() {
        target.action = action
        target.isCancel = isCancel
    }
}

/// The highlight: the game's amber, just outside the button's own bevel.
private struct FocusRing: View {
    @ObservedObject var scope: MenuFocusScope
    let target: MenuTarget

    var body: some View {
        if scope.focused === target {
            Rectangle()
                .stroke(Retro.amber, lineWidth: 3)
                .padding(-5)
                .allowsHitTesting(false)
        }
    }
}
