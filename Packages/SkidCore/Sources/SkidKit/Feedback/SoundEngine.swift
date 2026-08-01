import AVFoundation
import Foundation
import SkidCore

/// Procedural race audio — no audio assets, in the same spirit as the
/// graphics: one `AVAudioSourceNode` synthesizes everything.
///
/// - Engine: two slightly detuned saw oscillators, pitch and volume driven
///   by the lead human car's speed.
/// - Skid: filtered white noise, gain driven by the largest human slip.
/// - Impacts: short noise-burst envelopes triggered by `RaceEvent`s.
///
/// The render block runs on the audio thread; it reads targets through a
/// lock and smooths them per-sample, so the tick loop can update freely.
@MainActor
public final class SoundEngine {
    struct Mix {
        var engineHz: Double = 0
        var engineGain: Double = 0
        var skidGain: Double = 0
        var thump: Double = 0
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var mix = Mix()

        func set(engineHz: Double, engineGain: Double, skidGain: Double) {
            lock.lock()
            mix.engineHz = engineHz
            mix.engineGain = engineGain
            mix.skidGain = skidGain
            lock.unlock()
        }

        func addThump(_ amount: Double) {
            lock.lock()
            mix.thump = min(1, mix.thump + amount)
            lock.unlock()
        }

        func read() -> Mix {
            lock.lock()
            defer { lock.unlock() }
            let value = mix
            mix.thump = 0  // consumed by the render thread
            return value
        }
    }

    private let engine = AVAudioEngine()
    private let state = State()
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        #if os(iOS)
        // Ambient: respects the silent switch, mixes with the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let format = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100
        let node = makeSourceNode(sampleRate: sampleRate)
        engine.attach(node)
        engine.connect(
            node, to: engine.mainMixerNode,
            format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        engine.mainMixerNode.outputVolume = 0.5
        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    public func stop() {
        guard running else { return }
        engine.stop()
        running = false
    }

    /// Feed the mix from the latest sim state (call once per tick).
    public func update(race: Race, humanCount: Int, paused: Bool) {
        guard running else { return }
        if paused {
            state.set(engineHz: 0, engineGain: 0, skidGain: 0)
            return
        }
        let humans = race.cars.prefix(max(1, humanCount))
        let leadSpeed = humans.first?.state.velocity.length ?? 0
        let maxSlip = humans.map(\.state.slipSpeed).max() ?? 0
        let engineHz = 55 + leadSpeed * 0.32
        let engineGain = min(0.30, 0.10 + leadSpeed / 2400)
        let skidGain = maxSlip > 90 ? min(0.22, (maxSlip - 90) / 900) : 0
        state.set(engineHz: engineHz, engineGain: engineGain, skidGain: skidGain)
        for event in race.lastEvents {
            switch event {
            case .wallImpact(let id, let speed) where id.rawValue < humanCount:
                state.addThump(min(1, speed / 400))
            case .carImpact(let a, let b, let closing)
            where a.rawValue < humanCount || b.rawValue < humanCount:
                state.addThump(min(1, closing / 350))
            default:
                break
            }
        }
    }

    private func makeSourceNode(sampleRate: Double) -> AVAudioSourceNode {
        let state = self.state
        var phase1 = 0.0
        var phase2 = 0.0
        var smoothedHz = 55.0
        var smoothedEngine = 0.0
        var smoothedSkid = 0.0
        var noiseFilter = 0.0
        var thumpEnv = 0.0
        var seed: UInt64 = 0x9E37_79B9
        return AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let targets = state.read()
            thumpEnv = min(1, thumpEnv + targets.thump)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            for frame in 0..<Int(frameCount) {
                // Per-sample smoothing keeps pitch/gain changes click-free.
                smoothedHz += (targets.engineHz - smoothedHz) * 0.0004
                smoothedEngine += (targets.engineGain - smoothedEngine) * 0.0008
                smoothedSkid += (targets.skidGain - smoothedSkid) * 0.0015
                thumpEnv *= 0.9996

                // Two detuned saws — a cheap, angry little engine.
                phase1 += smoothedHz / sampleRate
                phase2 += smoothedHz * 1.011 / sampleRate
                phase1 -= phase1.rounded(.down)
                phase2 -= phase2.rounded(.down)
                let saws = (phase1 * 2 - 1) + (phase2 * 2 - 1) * 0.6

                // xorshift noise, low-passed for skid, raw-ish for thumps.
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                let white = Double(Int64(bitPattern: seed % 2000) - 1000) / 1000
                noiseFilter += (white - noiseFilter) * 0.12

                let sample =
                    saws * smoothedEngine * 0.5
                    + noiseFilter * smoothedSkid
                    + white * thumpEnv * 0.5
                out[frame] = Float(max(-1, min(1, sample)))
            }
            return noErr
        }
    }
}
