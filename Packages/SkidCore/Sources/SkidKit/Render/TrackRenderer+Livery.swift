import SkidCore
import SwiftUI

/// **The car's two tones, as the renderer needs them.**
///
/// Its own file for the reason the rest of `TrackRenderer` is split: the base file is
/// at its length budget. It also draws a real seam — everything here is the *livery*
/// (which tone goes where, and the seat/colour bookkeeping), while
/// `TrackRenderer+Cars` is the car's geometry.
extension TrackRenderer {
    /// The **nose** tone for each seat, derived by `CarLivery` — the front half of the
    /// two-tone body, and the facing cue that replaced the white sheen.
    ///
    /// Precomputed alongside the base rather than derived per frame: the derivation is
    /// a Lab round trip per car, on a path that runs at 60 Hz.
    static let carNosePalette: [Color] = CarPalette.paints.map {
        let nose = CarLivery.nose(of: $0)
        return Color(red: nose.red, green: nose.green, blue: nose.blue)
    }

    /// The nose tone to pair with `base` for the car in `seat`, or nil for a
    /// **single-tone** car.
    ///
    /// **Derived from the seat, not from the `Color`.** A `SwiftUI.Color` is opaque —
    /// its components cannot be read back before iOS 17, and this target is iOS 16 —
    /// so the livery cannot be computed from whatever colour the scene supplies. Every
    /// colour in the game comes from `CarPalette` by index today, so the index is the
    /// honest key; when a picker lets a player choose, it should hand the renderer a
    /// palette *index* (or a `CarPalette.Paint`) rather than a resolved `Color`, for
    /// exactly this reason.
    ///
    /// A colour that is *not* this seat's palette entry returns nil and the car draws
    /// in one tone. Deliberately not a guessed nose: a tone derived from a different
    /// seat's paint would be a wrong colour presented as a livery, whereas single-tone
    /// is a supported look rather than a visible fault.
    static func nose(forSeat seat: Int, base: Color?) -> Color? {
        let palette = carPalette[seat % carPalette.count]
        guard base == nil || base == palette else { return nil }
        return carNosePalette[seat % carNosePalette.count]
    }

    /// Paint the body's two tones into an already-clipped, already-oriented context.
    ///
    /// Split out of `draw(car:…)` on the function-length limit, and it stands alone
    /// cleanly: the caller owns the car's transform and silhouette, this owns the
    /// division between front and back.
    static func paintLivery(
        base: Color, nose: Color?, length: Double, width: Double,
        into livery: inout GraphicsContext
    ) {
        guard let nose else { return }
        livery.fill(
            Path(CGRect(x: 0, y: -width / 4, width: length / 2, height: width / 2)),
            with: .color(nose))
        // A soft seam so the two tones meet as a painted division rather than a hard
        // join that reads as two stacked sprites at editor zoom.
        livery.fill(
            Path(CGRect(x: -3, y: -width / 4, width: 6, height: width / 2)),
            with: .linearGradient(
                Gradient(colors: [base, nose]),
                startPoint: CGPoint(x: -3, y: 0), endPoint: CGPoint(x: 3, y: 0)))
    }

    /// The lamp dots at the nose tip — flavor at editor zoom, and now the only white
    /// on the car. A pair of points cannot wash out a palette the way the deleted
    /// half-body gradient did.
    static func paintLamps(length: Double, into livery: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let lamp = CGRect(x: length / 2 - 6, y: side * 3.4 - 1.9, width: 3.8, height: 3.8)
            livery.fill(
                Path(ellipseIn: lamp), with: .color(Color(red: 1, green: 0.98, blue: 0.82)))
        }
    }

    /// **Travelling backwards, which is not the same question as facing.**
    ///
    /// Reported from device: it is easy to reverse by accident and not notice. Neither
    /// the livery nor a headlight would show it — both say which way the car *points*,
    /// and in a drift game a car often points one way while moving another.
    /// `forwardSpeed` is velocity along the car's own axis, so a negative value is
    /// precisely "going backwards", whatever the throttle is doing.
    ///
    /// Drawn as reversing lamps at the tail, where a driver already looks for them.
    static func paintReverseLamps(
        car: CarState, length: Double, into livery: inout GraphicsContext
    ) {
        guard car.forwardSpeed < -reverseCueSpeed else { return }
        for side in [-1.0, 1.0] {
            let lamp = CGRect(
                x: -length / 2 + 2.2, y: side * 3.4 - 1.9, width: 3.8, height: 3.8)
            livery.fill(Path(ellipseIn: lamp), with: .color(.white.opacity(0.95)))
        }
    }

    /// Below this speed along its own axis, a car is not shown as reversing.
    ///
    /// A car nudging a wall or settling on a slope crosses zero constantly, and a lamp
    /// that flickers with float noise reads as a rendering fault rather than a gear.
    /// 12 units/s is well under `reverseMaxSpeed` (140) but clear of that jitter.
    static let reverseCueSpeed = 12.0
}
