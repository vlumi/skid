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
        var engineDuty: Double = 0.3
        var engineGain: Double = 0
        var skidGain: Double = 0
        var thump: Double = 0
        /// A start beep to fire, as (pitch, loudness). Consumed by the render thread
        /// like `thump`, so a beep sounds once however many buffers go by.
        var beepHz: Double = 0
        var beepGain: Double = 0
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var mix = Mix()

        func set(
            engineHz: Double, engineDuty: Double, engineGain: Double, skidGain: Double
        ) {
            lock.lock()
            mix.engineHz = engineHz
            mix.engineDuty = engineDuty
            mix.engineGain = engineGain
            mix.skidGain = skidGain
            lock.unlock()
        }

        func addThump(_ amount: Double) {
            lock.lock()
            mix.thump = min(1, mix.thump + amount)
            lock.unlock()
        }

        func beep(hz: Double, gain: Double) {
            lock.lock()
            mix.beepHz = hz
            mix.beepGain = gain
            lock.unlock()
        }

        func read() -> Mix {
            lock.lock()
            defer { lock.unlock() }
            let value = mix
            mix.thump = 0  // consumed by the render thread
            mix.beepGain = 0  // ditto — a beep triggers once
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
    /// **A start beep.** `final` is the lights-out one: higher and louder, so "go" is
    /// audibly different from the counting rather than a fourth identical blip — the
    /// moment you are listening for is the one that sounds unlike the others.
    public func startBeep(final isFinal: Bool) {
        guard running else { return }
        state.beep(hz: isFinal ? 1320 : 660, gain: isFinal ? 0.9 : 0.5)
    }

    public func update(race: Race, humanCount: Int, paused: Bool) {
        guard running else { return }
        if paused {
            state.set(engineHz: 0, engineDuty: 0.3, engineGain: 0, skidGain: 0)
            return
        }
        let humans = race.cars.prefix(max(1, humanCount))
        let leadSpeed = humans.first?.state.velocity.length ?? 0
        let maxSlip = humans.map(\.state.slipSpeed).max() ?? 0
        let engineHz = EngineVoice.hz(forSpeed: leadSpeed)
        let engineDuty = EngineVoice.duty(forSpeed: leadSpeed)
        // Raised after measuring: the old chain halved 0.10…0.30 again at the mix, so
        // the engine rendered at 4–9% peak — inaudible against a countdown beep at 31%
        // on a phone speaker. It is the constant bed, so it sits under the beeps, but
        // it has to be there.
        let engineGain = min(0.55, 0.22 + leadSpeed / 900)
        let skidGain = maxSlip > 90 ? min(0.22, (maxSlip - 90) / 900) : 0
        state.set(
            engineHz: engineHz, engineDuty: engineDuty, engineGain: engineGain,
            skidGain: skidGain)
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

    /// One xorshift noise sample in -1…1 — low-passed for skid, raw-ish for thumps.
    /// Advances `seed` in place.
    private nonisolated static func noise(_ seed: inout UInt64) -> Double {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Double(Int64(bitPattern: seed % 2000) - 1000) / 1000
    }

    private func makeSourceNode(sampleRate: Double) -> AVAudioSourceNode {
        let state = self.state
        var phase1 = 0.0
        var subPhase = 0.0
        var smoothedHz = EngineVoice.idleHz
        var smoothedDuty = 0.3
        var smoothedEngine = 0.0
        var smoothedSkid = 0.0
        var noiseFilter = 0.0
        var thumpEnv = 0.0
        var beep = BeepVoice.Playing()
        var seed: UInt64 = 0x9E37_79B9
        return AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let targets = state.read()
            thumpEnv = min(1, thumpEnv + targets.thump)
            if targets.beepGain > 0 {
                beep.start(hz: targets.beepHz, gain: targets.beepGain, rate: sampleRate)
            }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            for frame in 0..<Int(frameCount) {
                // Per-sample smoothing keeps pitch/gain changes click-free.
                smoothedHz += (targets.engineHz - smoothedHz) * 0.0004
                smoothedDuty += (targets.engineDuty - smoothedDuty) * 0.0004
                smoothedEngine += (targets.engineGain - smoothedEngine) * 0.0008
                smoothedSkid += (targets.skidGain - smoothedSkid) * 0.0015
                thumpEnv *= 0.9996

                // A pulse and a square an octave down — see `EngineVoice`.
                phase1 += smoothedHz / sampleRate
                subPhase += smoothedHz * 0.5 / sampleRate
                phase1 -= phase1.rounded(.down)
                subPhase -= subPhase.rounded(.down)
                let engine = EngineVoice.sample(
                    phase: phase1, subPhase: subPhase, duty: smoothedDuty)

                let white = SoundEngine.noise(&seed)
                noiseFilter += (white - noiseFilter) * 0.12

                let sample =
                    engine * smoothedEngine * 0.5
                    + noiseFilter * smoothedSkid
                    + white * thumpEnv * 0.5
                    + beep.sample(rate: sampleRate)
                // **Soft limit, not a hard clamp.** Measured: engine + skid + a thump
                // sums to 0.995, and a countdown beep landing during a slide-and-hit
                // pushes it to 1.31 — which `max(-1, min(1,))` turns into square-wave
                // distortion at the loudest moment of the race. `tanh` bends the peaks
                // instead, so a busy moment gets louder rather than broken.
                out[frame] = Float(tanh(sample))
            }
            return noErr
        }
    }
}
