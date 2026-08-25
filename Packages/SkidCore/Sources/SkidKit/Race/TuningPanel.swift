import SkidCore
import SwiftUI

/// The on-device control-tuning playground, reached from the pause menu.
/// Everything here exists to be A/B-ed on real thumbs before the scheme
/// verdict; d-pad dials apply live, pace applies on Reset.
struct TuningPanel: View {
    @ObservedObject var settings: GameSettings
    let close: () -> Void
    /// Throw away every stored track, record and dial. Nil where there is no game to
    /// reset, which is how the panel stays usable without one.
    var resetAllData: (() -> Void)?

    /// Guards the wipe behind a second tap: it is irreversible, and it sits on a panel
    /// opened by shaking the phone.
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // **First, because it is the one thing here reached mid-diagnosis.**
                    // The overlay is what you turn on to SEE a bug, and it used to sit
                    // below twenty sliders — a scroll every time, on a panel opened
                    // precisely because something looked wrong.
                    section(Text("Debug", bundle: .module))
                    Toggle(isOn: $settings.debugOverlay) {
                        Text("Show sim overlay", bundle: .module)
                            .font(.footnote).foregroundColor(.white)
                    }
                    .tint(.orange)
                    .padding(.horizontal, 4)

                    section(Text("Casual", bundle: .module))
                    slider(
                        Text("Flip rate", bundle: .module), value: $settings.aimTurnRate,
                        range: 0...16, step: 0.5, format: "%.1f")
                    slider(
                        Text("Speed boost", bundle: .module), value: $settings.aimFlipBoost,
                        range: 0...16, step: 0.5, format: "%.1f")
                    slider(
                        Text("Drift keep", bundle: .module), value: $settings.driftRetention,
                        range: 0...1, step: 0.05, format: "%.2f")
                    slider(
                        Text("Grip", bundle: .module), value: $settings.gripScale,
                        range: 0.2...2, step: 0.05, format: "%.2f")
                    slider(
                        Text("Reverse under speed", bundle: .module),
                        value: $settings.aimReverseBelowSpeed,
                        range: 30...150, step: 5, format: "%.0f")
                    slider(
                        Text("Gas ease", bundle: .module), value: $settings.aimThrottleEase,
                        range: 0...1, step: 0.05, format: "%.2f")
                    slider(
                        Text("Forward arc", bundle: .module),
                        value: $settings.aimForwardArcDegrees,
                        range: 90...170, step: 5, format: "%.0f°")
                    slider(
                        Text("Tail swing", bundle: .module),
                        value: $settings.aimTailSwingDegrees,
                        range: 20...120, step: 5, format: "%.0f°")

                    // **The pad is being redesigned on device**, so its layout
                    // dials are here rather than baked: a floating pad's centre
                    // is a point on glass with nothing to feel for, and neither
                    // longer travel nor a self-centring wheel fixed the sine
                    // curve that causes. The zone-strip model is the third try
                    // and the first that gives the thumb an EDGE to find, so
                    // what these want is driving, not more arithmetic.
                    section(Text("Pro layout", bundle: .module))
                    steerModelRow
                    slider(
                        Text("Steer travel", bundle: .module),
                        value: $settings.dpadSteerTravel,
                        range: 20...160, step: 5, format: "%.0f")
                    slider(
                        Text("Recentring", bundle: .module),
                        value: $settings.dpadSteerRecentring,
                        range: 0...4, step: 0.1, format: "%.1f")
                    slider(
                        Text("Speed effect", bundle: .module),
                        value: $settings.dpadRecentringSpeed,
                        range: 0...1, step: 0.05, format: "%.2f")
                    modelRow
                    slider(
                        Text("Cruise strip", bundle: .module),
                        value: $settings.dpadCruiseStrip,
                        range: 0...0.5, step: 0.05, format: "%.2f")
                    slider(
                        Text("Brake band", bundle: .module), value: $settings.dpadBrakeBand,
                        range: 0.1...0.45, step: 0.05, format: "%.2f")
                    slider(
                        Text("Gas steering", bundle: .module),
                        value: $settings.dpadSteerAtFullThrottle,
                        range: 0...1, step: 0.05, format: "%.2f")
                    slider(
                        Text("Gas recentring", bundle: .module),
                        value: $settings.dpadThrottleRecentring,
                        range: 0...6, step: 0.25, format: "%.2f")

                    section(Text("Pro", bundle: .module))
                    slider(
                        Text("Dead zone", bundle: .module), value: $settings.dpadDeadzone,
                        range: 2...24, step: 1, format: "%.0f")
                    slider(
                        Text("Travel", bundle: .module), value: $settings.dpadTravel,
                        range: 32...80, step: 2, format: "%.0f")
                    stepsRow
                    slider(
                        Text("Curve", bundle: .module), value: $settings.dpadExpo,
                        range: 1.0...2.5, step: 0.1, format: "%.1f")
                    slider(
                        Text("Turn rate", bundle: .module), value: $settings.turnRate,
                        range: 2...6, step: 0.1, format: "%.1f")
                    slider(
                        Text("Flip", bundle: .module), value: $settings.steerFlipBoost,
                        range: 0...12, step: 0.5, format: "%.1f")

                    // Only the two knobs device play could actually tell apart. The
                    // others (glance bounce, scrape, nose pull) are real terms but
                    // their effect wasn't distinguishable while driving, so they keep
                    // good defaults rather than taking up slider space — they are
                    // still settable in `CarTuning` if that changes.
                    section(Text("Walls", bundle: .module))
                    slider(
                        Text("Bounce", bundle: .module), value: $settings.wallRestitution,
                        range: 0...1, step: 0.05, format: "%.2f")
                    slider(
                        Text("Drag floor", bundle: .module), value: $settings.wallDragFloor,
                        range: 0...1, step: 0.05, format: "%.2f")

                    section(Text("Air", bundle: .module))
                    slider(
                        Text("Gravity", bundle: .module), value: $settings.gravity,
                        range: 4...48, step: 1, format: "%.0f")

                    section(Text("Pace", bundle: .module))
                    slider(
                        Text("Pace", bundle: .module), value: $settings.pace,
                        range: 0.6...1.0, step: 0.05, format: "%.2f")

                    section(Text("Elevation", bundle: .module))
                    slider(
                        Text("Deck scale", bundle: .module), value: $settings.deckScale,
                        range: 1.0...1.6, step: 0.05, format: "%.2f")

                    // **Last thing in the scroll, not pinned.** Erasing everything is a
                    // rare, irreversible act; it belongs where you have to go looking for
                    // it, rather than sitting under your thumb the whole time you are
                    // dragging sliders.
                    resetAllDataLink
                }
            }
            .frame(maxHeight: 460)
            Text("Physics dials apply on Reset; hiscores need stock", bundle: .module)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            // Floating footer: leaving, and undoing. Both are wanted from anywhere in the
            // list, so they do not scroll away.
            HStack(spacing: 12) {
                Button(action: close) {
                    Text("Back", bundle: .module).pillStyle()
                }
                // **The way back.** The dials persist, so a phone that has been
                // experimented with stays that way — and a tuned car records no times,
                // which is a silent failure with no obvious cure. Covers the whole panel,
                // not only the physics: the aim shape, the d-pad, elevation and pace are
                // just as tuned, and a reset that left them was a half restore.
                Button {
                    settings.resetAllTunings()
                } label: {
                    Text("Reset to defaults", bundle: .module).pillStyle()
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
        // Push the elevation knob into the renderer's global as it's dragged,
        // so the deck/car scale updates live.
        .onChangeCompat(of: settings.deckScale) { _ in settings.applyRenderTuning() }
    }

    /// **Wipe every stored track, record and dial** — a development tool, so it reads as a
    /// link rather than a button: the panel's real controls are the sliders and the two
    /// footer pills, and this is neither.
    ///
    /// Armed by a first tap, because it cannot be undone. The armed state names what will
    /// go, since "everything" is easy to read as "the dials" on a panel full of dials, and
    /// it offers no Cancel of its own — tapping the link again disarms it, and the footer
    /// already has the one way out. Two buttons that both mean "never mind" is what the
    /// first version had, and it read as a mistake.
    @ViewBuilder private var resetAllDataLink: some View {
        if let resetAllData {
            VStack(spacing: 8) {
                Divider().overlay(.white.opacity(0.2))
                if confirmingReset {
                    Text("Deletes your tracks, records and profiles", bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button {
                        confirmingReset = false
                        resetAllData()
                        close()
                    } label: {
                        Text("Erase everything", bundle: .module)
                            .font(.footnote.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Button {
                        confirmingReset = false
                    } label: {
                        Text("Never mind", bundle: .module)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Button {
                        confirmingReset = true
                    } label: {
                        Text("Erase all data", bundle: .module)
                            .font(.footnote)
                            .underline()
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func section(_ label: Text) -> some View {
        label
            .font(.caption.bold())
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Steps per axis: full analog or 1–3 quantized notches.
    /// Which meaning depth has — the fork worth driving rather than deciding
    /// in the abstract. See `VirtualDPadControlSource.DepthMeaning`.
    /// Which steering the band uses — the fork the last device round opened:
    /// hold an offset (from entry) or wind by movement (follow moves).
    private var steerModelRow: some View {
        HStack(spacing: 8) {
            Text("Steering", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
            Spacer(minLength: 8)
            ForEach(VirtualDPadControlSource.SteerModel.allCases, id: \.rawValue) { mode in
                let on = settings.dpadSteerModel == mode.rawValue
                Button {
                    settings.dpadSteerModel = mode.rawValue
                } label: {
                    (mode == .fromEntry
                        ? Text("From entry", bundle: .module)
                        : Text("Follow moves", bundle: .module))
                        .font(Retro.caption)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 30)
                        .background(on ? Retro.highlight : Retro.panel)
                        .overlay(RetroBevel(inset: on, thickness: 2))
                        .foregroundStyle(on ? Retro.onHighlight : Retro.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modelRow: some View {
        HStack(spacing: 8) {
            Text("Depth", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
            Spacer(minLength: 8)
            ForEach(VirtualDPadControlSource.DepthMeaning.allCases, id: \.rawValue) { mode in
                let on = settings.dpadDepthMeaning == mode.rawValue
                Button {
                    settings.dpadDepthMeaning = mode.rawValue
                } label: {
                    (mode == .steerOnly
                        ? Text("Steer only", bundle: .module)
                        : Text("Gas + grip", bundle: .module))
                        .font(Retro.caption)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 30)
                        .background(on ? Retro.highlight : Retro.panel)
                        .overlay(RetroBevel(inset: on, thickness: 2))
                        .foregroundStyle(on ? Retro.onHighlight : Retro.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stepsRow: some View {
        VStack(spacing: 6) {
            Text("Steps", bundle: .module)
                .font(.footnote.bold())
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 8) {
                stepChoice(label: Text("Analog", bundle: .module), value: 0)
                ForEach(1...3, id: \.self) { count in
                    stepChoice(label: Text(verbatim: "\(count)"), value: count)
                }
            }
        }
    }

    private func stepChoice(label: Text, value: Int) -> some View {
        Button {
            settings.dpadSteps = value
        } label: {
            label
                .font(.callout.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    settings.dpadSteps == value
                        ? Color.white.opacity(0.9) : .black.opacity(0.3),
                    in: Capsule()
                )
                .foregroundStyle(settings.dpadSteps == value ? .black : .white)
        }
    }

    private func slider(
        _ label: Text, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
        format: String
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                label.font(.footnote.bold())
                Spacer()
                Text(verbatim: String(format: format, value.wrappedValue))
                    .font(.footnote.monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.85))
            Slider(value: value, in: range, step: step)
                .tint(.white.opacity(0.8))
        }
    }
}
