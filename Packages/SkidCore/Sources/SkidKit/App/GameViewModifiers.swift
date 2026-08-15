import SwiftUI

extension View {
    func statusBarHiddenIfAvailable() -> some View {
        #if os(iOS)
        return statusBarHidden(true)
        #else
        return self
        #endif
    }

    /// Thumbs live at the screen edges during play: make system edge swipes
    /// (home indicator, notification/control center) require the deliberate
    /// double-swipe — but only while actually racing. Menus, pause, and
    /// results keep normal one-swipe system gestures.
    func defersEdgeSwipes(_ active: Bool) -> some View {
        #if os(iOS)
        return defersSystemGestures(on: active ? .all : [])
        #else
        return self
        #endif
    }

    /// Name-entry keyboard hints, which are iOS-only API — SkidKit also builds for
    /// macOS, where the platform handles all three itself.
    func nameFieldStyle() -> some View {
        #if os(iOS)
        return textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
        #else
        return self
        #endif
    }

    /// The standard button face. **Square and beveled, not a capsule** — this is the one
    /// seam every screen's buttons already ran through, so converting it is what turned
    /// the menus retro in one move rather than screen by screen. See `Retro`.
    func pillStyle() -> some View {
        font(Retro.font(14))
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(Retro.panel)
            .overlay(RetroBevel(thickness: 2))
            .foregroundStyle(Retro.ink)
    }
}
