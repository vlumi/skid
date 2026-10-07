import AVFoundation
import XCTest

@testable import SkidKit

/// The race's audio is rendered on the audio thread, never the main one — and
/// under Swift 6 a render block that inherited the main actor traps there.
/// This pulls buffers from the real node on a thread of its own.
@MainActor
final class SoundRenderThreadTests: XCTestCase {
    func testTheNodeRendersOffTheMainThread() throws {
        let rate = 44100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let state = SoundEngine.State()
        state.beep(hz: 880, gain: 1)
        nonisolated(unsafe) let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let node = SoundEngine.makeSourceNode(sampleRate: rate, state: state)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        defer { engine.stop() }
        nonisolated(unsafe) let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))

        // A Thread, not `DispatchQueue.sync`: GCD may run a sync block on the
        // calling (main) thread, which would pass for the wrong reason.
        let rendered = expectation(description: "rendered")
        nonisolated(unsafe) var status: AVAudioEngineManualRenderingStatus?
        nonisolated(unsafe) var onMain = true
        Thread {
            onMain = Thread.isMainThread
            status = try? engine.renderOffline(1024, to: buffer)
            rendered.fulfill()
        }.start()
        wait(for: [rendered], timeout: 5)

        XCTAssertFalse(onMain, "rendered on the main thread — the test proves nothing")
        XCTAssertEqual(status, .success)
        let samples = UnsafeBufferPointer(
            start: buffer.floatChannelData?[0], count: Int(buffer.frameLength))
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.01, "the beep never sounded")
    }
}
