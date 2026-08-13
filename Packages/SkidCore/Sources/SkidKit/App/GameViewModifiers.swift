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

    func pillStyle() -> some View {
        font(.callout.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.35), in: Capsule())
            .foregroundStyle(.white)
    }
}
