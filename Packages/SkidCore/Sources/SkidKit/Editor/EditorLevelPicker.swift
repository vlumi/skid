import SkidCore
import SwiftUI

/// **The level jump list** — what a long-press on the Levels button opens, so a
/// deep storey is one gesture instead of cycling the whole ring. Its options come
/// from `LevelFilter.pickerOptions`, the same states the tap-cycle walks.
extension EditorView {
    var levelPickerGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(
                LevelFilter.pickerOptions(usedLevels: usedLevels()), id: \.self
            ) { option in
                Button {
                    levelFilter = option
                    configuring = nil
                } label: {
                    levelOption(option, chosen: levelFilter == option)
                }
            }
        }
    }

    /// One option in the jump list.
    private func levelOption(_ option: LevelFilter, chosen: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: option == .off ? "square.slash" : "square.3.layers.3d")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(option == .off ? 0.6 : 1))
                .frame(width: 44, height: 44)
            switch option {
            case .off: Text("Off", bundle: .module).font(.caption2).foregroundColor(.white)
            case .all: Text("All", bundle: .module).font(.caption2).foregroundColor(.white)
            case .storey(let level):
                Text(verbatim: "\(level)").font(.caption2).foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            chosen ? Color.white.opacity(0.18) : .black.opacity(0.25),
            in: RoundedRectangle(cornerRadius: 8))
    }
}
