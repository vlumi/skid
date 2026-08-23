import SwiftUI

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
import AVFoundation

/// **The camera, looking for one thing.**
///
/// A `UIViewRepresentable` over `AVCaptureSession` rather than the Vision
/// framework: metadata output already recognises QR codes in hardware, arrives
/// on a delegate callback, and needs no per-frame image handling — which is the
/// difference between a scanner that costs nothing and one that competes with
/// the game for the GPU.
///
/// Reports every code it sees; the caller decides what to do about repeats. That
/// split keeps the "is this a track?" question out of the camera plumbing.
struct QRScannerView: UIViewRepresentable {
    /// Called on the main actor for each code read.
    let onCode: (String) -> Void
    /// Called once if the camera cannot be used at all, with something to show.
    let onFailure: (String) -> Void

    func makeUIView(context: Context) -> ScannerUIView {
        let view = ScannerUIView()
        view.onCode = onCode
        view.onFailure = onFailure
        view.start()
        return view
    }

    func updateUIView(_ view: ScannerUIView, context: Context) {}

    static func dismantleUIView(_ view: ScannerUIView, coordinator: ()) {
        // **Stopped when the view goes away**, or the camera stays live behind
        // the sheet — a green dot on the status bar with nothing using it is
        // exactly the kind of thing that reads as spyware.
        view.stop()
    }

    /// The preview layer and the session that feeds it.
    final class ScannerUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        var onFailure: ((String) -> Void)?
        private let session = AVCaptureSession()

        // UIKit requires this as an overridable `class var`; `static` would not
        // override anything, so the usual preference does not apply.
        // swiftlint:disable:next static_over_final_class
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        private var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer  // swiftlint:disable:this force_cast
        }

        func start() {
            guard let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                onFailure?(String(localized: "No camera available.", bundle: .module))
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onFailure?(String(localized: "The camera could not be started.", bundle: .module))
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            // Set AFTER adding the output, or the type is not yet available and
            // this throws — the classic ordering trap with this API.
            output.metadataObjectTypes = [.qr]
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            // Off the main thread: `startRunning` blocks until the camera is
            // configured, which is long enough to drop frames of the UI.
            Task.detached { [session] in session.startRunning() }
        }

        func stop() {
            guard session.isRunning else { return }
            Task.detached { [session] in session.stopRunning() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            for object in objects {
                guard let code = object as? AVMetadataMachineReadableCodeObject,
                    code.type == .qr, let text = code.stringValue
                else { continue }
                onCode?(text)
            }
        }
    }
}
#endif
