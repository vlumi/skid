import SkidCore
import SwiftUI

/// The on-device control-tuning playground, reached from the pause menu.
/// Everything here exists to be A/B-ed on real thumbs before the scheme
/// verdict; d-pad dials apply live, pace applies on Reset.
struct TuningPanel: View {
    @ObservedObject var settings: GameSettings
    let close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
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
            VStack(spacing: 2) {
                slider(
                    Text("Pace", bundle: .module), value: $settings.pace,
                    range: 0.6...1.0, step: 0.05, format: "%.2f")
                Text("Pace applies on Reset", bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Button(action: close) {
                Text("Back", bundle: .module).pillStyle()
            }
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
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
