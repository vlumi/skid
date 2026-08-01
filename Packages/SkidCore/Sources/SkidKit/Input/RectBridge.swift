import CoreGraphics
import SkidCore

extension CGRect {
    /// The core's rect, for handing screen geometry to the control schemes.
    var asRect: Rect {
        Rect(x: origin.x, y: origin.y, width: width, height: height)
    }
}
