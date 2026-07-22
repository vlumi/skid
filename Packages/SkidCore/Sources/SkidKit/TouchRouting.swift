import SkidCore
import SwiftUI

#if os(iOS)
import UIKit

/// Captures every simultaneous touch and streams id-tagged events — the
/// couch-multiplayer input surface (SwiftUI gestures only track one touch).
struct MultiTouchSurface: UIViewRepresentable {
    let rig: CouchRig

    func makeUIView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.rig = rig
        return view
    }

    func updateUIView(_ view: TouchCaptureView, context: Context) {
        view.rig = rig
    }
}

final class TouchCaptureView: UIView {
    weak var rig: CouchRig?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private func touchID(_ touch: UITouch) -> TouchID {
        ObjectIdentifier(touch).hashValue
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            rig?.touchBegan(id: touchID(touch), at: Vec2(p.x, p.y))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            rig?.touchMoved(id: touchID(touch), at: Vec2(p.x, p.y))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            rig?.touchEnded(id: touchID(touch))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            rig?.touchEnded(id: touchID(touch))
        }
    }
}
#endif

/// The input surface for the race screen: real multitouch on iOS, a
/// single-pointer fallback elsewhere (macOS build keeps compiling; real
/// Mac input arrives with the keyboard/controller milestone).
struct InputSurface: View {
    let rig: CouchRig

    var body: some View {
        #if os(iOS)
        MultiTouchSurface(rig: rig)
        #else
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let location = Vec2(value.location.x, value.location.y)
                        // First change begins the touch (no-op afterwards),
                        // later ones just move it.
                        rig.touchBegan(id: 0, at: location)
                        rig.touchMoved(id: 0, at: location)
                    }
                    .onEnded { _ in
                        rig.touchEnded(id: 0)
                    }
            )
        #endif
    }
}
