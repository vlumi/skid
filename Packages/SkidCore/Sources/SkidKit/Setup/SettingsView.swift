import SkidCore
import SwiftUI

/// **The settings screen: the handful of things that are true between races.**
///
/// Deliberately short. Anything that belongs to a *race* (mode, track, who is playing)
/// lives on the setup screen, and anything that is a development dial lives in the tuning
/// panel behind a shake. What is left is the device: how it sounds, how it buzzes, and
/// how two people sit around it.
///
/// The look is `Retro` — see there for why the menus stopped looking like iOS.
struct SettingsView: View {
    @ObservedObject var game: CouchGame
    @ObservedObject var settings: GameSettings
    let close: () -> Void
    /// Shown as a row, so About is reachable without another front-door button.
    let showAbout: () -> Void

    /// Arms the wipe. Irreversible, so it takes a second tap — and it sits at the very
    /// bottom, after everything you might actually have come here for.
    @State private var confirmingReset = false

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    titleBar
                    audioPanel
                    seatingPanel
                    aboutRow
                    dangerPanel
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var titleBar: some View {
        Text("SETTINGS", bundle: .module)
            .font(Retro.title)
            .foregroundStyle(Retro.onHighlight)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Retro.highlight)
            .overlay(RetroBevel(inset: true, thickness: 2))
    }

    private var audioPanel: some View {
        VStack(spacing: 10) {
            heading(Text("AUDIO", bundle: .module))
            RetroToggle(label: Text("Sound", bundle: .module), isOn: $settings.soundOn)
            RetroToggle(label: Text("Haptics", bundle: .module), isOn: $settings.hapticsOn)
        }
        .retroPanel()
    }

    /// **Where the two-player layout finally lives.**
    ///
    /// It was a hardcoded `faceToFace = true` with no UI at all: the manual layout picker
    /// was retired from the setup screen (two players are always face-to-face, which is
    /// right by default), but "always" is wrong for two people sitting side by side on a
    /// sofa. It is a property of the room, not of the race — so it belongs here.
    private var seatingPanel: some View {
        VStack(spacing: 10) {
            heading(Text("TWO PLAYERS", bundle: .module))
            RetroChoice(
                label: Text("Face to face", bundle: .module),
                detail: Text("Across a table; the far controls turn around", bundle: .module),
                selected: game.faceToFace
            ) { game.faceToFace = true }
            RetroChoice(
                label: Text("Side by side", bundle: .module),
                detail: Text("Sharing one edge; both control pads face you", bundle: .module),
                selected: !game.faceToFace
            ) { game.faceToFace = false }
        }
        .retroPanel()
    }

    private var aboutRow: some View {
        Button(action: showAbout) {
            HStack {
                Text("About Skid Jam", bundle: .module)
                    .font(Retro.body)
                Spacer()
                Text(verbatim: "▸")
                    .font(Retro.body)
            }
            .foregroundStyle(Retro.ink)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(Retro.panel)
            .overlay(RetroBevel())
        }
        .buttonStyle(.plain)
    }

    /// Last, and visually apart: erasing everything is not a setting.
    private var dangerPanel: some View {
        VStack(spacing: 10) {
            heading(Text("DANGER", bundle: .module))
            if confirmingReset {
                Text("Deletes your tracks, records and profiles", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
                    .multilineTextAlignment(.center)
                Button {
                    confirmingReset = false
                    game.resetAllData()
                    close()
                } label: {
                    Text("ERASE EVERYTHING", bundle: .module)
                        .retroButton(wide: true, tint: Retro.danger)
                }
                .buttonStyle(.plain)
                Button {
                    confirmingReset = false
                } label: {
                    Text("Never mind", bundle: .module)
                        .font(Retro.caption)
                        .foregroundStyle(Retro.inkSoft)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    confirmingReset = true
                } label: {
                    Text("Erase all data", bundle: .module)
                        .font(Retro.body)
                        .foregroundStyle(Retro.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .retroPanel()
    }

    private var footer: some View {
        Button(action: close) {
            Text("BACK", bundle: .module).retroButton(wide: true)
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(Retro.ground.opacity(0.96))
    }

    private func heading(_ label: Text) -> some View {
        label
            .font(Retro.heading)
            .foregroundStyle(Retro.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: 8) {
                Text(verbatim: selected ? "▸" : " ")
                    .font(Retro.body)
                    .foregroundStyle(Retro.amber)
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
