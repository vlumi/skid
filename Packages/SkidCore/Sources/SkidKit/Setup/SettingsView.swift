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

    /// Arms the wipe. Irreversible, so it takes a second tap — and it sits at the very
    /// bottom, after everything you might actually have come here for.
    @State private var confirmingReset = false

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    RetroTitle(Text("Settings", bundle: .module))
                    audioPanel
                    seatingPanel
                    dangerPanel
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var audioPanel: some View {
        VStack(spacing: 10) {
            RetroHeading(Text("AUDIO", bundle: .module))
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
            RetroHeading(Text("TWO PLAYERS", bundle: .module))
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

    /// Last, and visually apart: erasing everything is not a setting.
    private var dangerPanel: some View {
        VStack(spacing: 10) {
            RetroHeading(Text("DANGER", bundle: .module))
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

}
