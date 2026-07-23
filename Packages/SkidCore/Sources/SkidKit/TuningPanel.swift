import SkidCore
import SwiftUI

/// The on-device control-tuning playground, reached from the pause menu.
/// Everything here exists to be A/B-ed on real thumbs before the scheme
/// verdict; d-pad dials apply live, pace applies on Reset.
struct TuningPanel: View {
    @ObservedObject var settings: GameSettings
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    section(Text("Aim", bundle: .module))
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
                        Text("Reverse under", bundle: .module),
                        value: $settings.aimReverseBelowSpeed,
                        range: 30...150, step: 5, format: "%.0f")
                    slider(
                        Text("Gas ease", bundle: .module), value: $settings.aimThrottleEase,
                        range: 0...1, step: 0.05, format: "%.2f")

                    section(Text("D-pad", bundle: .module))
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

                    section(Text("Pace", bundle: .module))
                    slider(
                        Text("Pace", bundle: .module), value: $settings.pace,
                        range: 0.6...1.0, step: 0.05, format: "%.2f")
                }
            }
            .frame(maxHeight: 460)
            Text("Physics dials apply on Reset; hiscores need stock", bundle: .module)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Button(action: close) {
                Text("Back", bundle: .module).pillStyle()
            }
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }

    private func section(_ label: Text) -> some View {
        label
            .font(.caption.bold())
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Steps per axis: full analog or 1–3 quantized notches.
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
