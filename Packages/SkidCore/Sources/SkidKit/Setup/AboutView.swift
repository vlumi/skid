import SkidCore
import SwiftUI

/// **About: what this is, whose it is, and which build you are looking at.**
///
/// The version is read from the bundle rather than written here, so it cannot disagree
/// with what shipped — the one fact on this screen a reader might actually rely on, and
/// the one most likely to rot if it were a literal.
struct AboutView: View {
    let close: () -> Void

    /// Marketing version and build, from the bundle. "—" when there is no bundle to read,
    /// which is the case in a preview or a unit test rather than in anything shipped.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case (let version?, let build?): return "v\(version) (\(build))"
        case (let version?, nil): return "v\(version)"
        default: return "—"
        }
    }

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    retroLeaveRow(retroClose(close)).padding(.horizontal, -16)
                    logo
                    blurb
                    creditsPanel
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }

        }
    }

    /// The title, drawn as the game's own rather than as a nav bar — this is the one
    /// screen where a bit of swagger belongs.
    private var logo: some View {
        VStack(spacing: 8) {
            RetroCheckers(rows: 2, cell: 6)
            Text(verbatim: "SKID JAM")
                .font(Retro.font(34, weight: .black))
                .foregroundStyle(Retro.amber)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(verbatim: AboutView.versionLine)
                .font(Retro.caption)
                .foregroundStyle(Retro.onGroundSoft)
            RetroCheckers(rows: 2, cell: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var blurb: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "A top-down arcade racer for one to four people around one phone.",
                bundle: .module
            )
            .font(Retro.body)
            .foregroundStyle(Retro.ink)
            Text(
                "Drift the corners, learn the lines, and build your own tracks in the editor.",
                bundle: .module
            )
            .font(Retro.caption)
            .foregroundStyle(Retro.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel()
    }

    private var creditsPanel: some View {
        VStack(spacing: 10) {
            Text("CREDITS", bundle: .module)
                .font(Retro.heading)
                .foregroundStyle(Retro.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            creditRow(Text("Made by", bundle: .module), Text(verbatim: "Ville Misaki"))
            creditRow(Text("Version", bundle: .module), Text(verbatim: AboutView.versionLine))
        }
        .retroPanel()
    }

    private func creditRow(_ label: Text, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            label
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
            Spacer(minLength: 12)
            value
                .font(Retro.body)
                .foregroundStyle(Retro.ink)
        }
        .frame(minHeight: 30)
    }

}
