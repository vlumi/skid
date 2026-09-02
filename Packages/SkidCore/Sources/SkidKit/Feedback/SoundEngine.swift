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
        var engines: [EngineTone] = []
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

        func set(engines: [EngineTone], skidGain: Double) {
            lock.lock()
            mix.engines = engines
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
            state.set(engines: [], skidGain: 0)
            return
        }
        state.set(
            engines: SoundEngine.engineTones(race: race),
            skidGain: SoundEngine.skidGain(race: race, humanCount: humanCount))
        note(events: race.lastEvents, humanCount: humanCount)
    }

    /// Thumps for contact, chirps for progress — the humans at this device.
    private func note(events: [RaceEvent], humanCount: Int) {
        var chirp: (hz: Double, gain: Double)?
        for event in events {
            switch event {
            case .wallImpact(let id, let speed) where id.rawValue < humanCount:
                state.addThump(min(1, speed / 400))
            case .carImpact(let a, let b, let closing)
            where a.rawValue < humanCount || b.rawValue < humanCount:
                state.addThump(min(1, closing / 350))
            // **Progress you can hear**, for the humans at this device. One
            // beep voice, so one tick picks its most important crossing: the
            // flag over the finish line over an intermediate gate.
            case .gateCrossed(let id) where id.rawValue < humanCount:
                if chirp == nil { chirp = (hz: 740, gain: 0.3) }
            case .lapCompleted(let id, _) where id.rawValue < humanCount:
                if (chirp?.hz ?? 0) < 1480 { chirp = (hz: 1480, gain: 0.6) }
            case .finished(let id) where id.rawValue < humanCount:
                chirp = (hz: 1760, gain: 0.9)
            default:
                break
            }
        }
        if let chirp {
            state.beep(hz: chirp.hz, gain: chirp.gain)
        }
    }

    /// **Every car's engine, not just P1's** — reported: the other seats were
    /// silent. Each car gets the voice its own speed asks for, at its seat's
    /// detune, and a car that has taken the flag is muted (the sim locks it to
    /// a stop; the sound should stop with it). Gain is budgeted across the
    /// grid so nine engines are a field, not nine times one engine's volume.
    static func engineTones(race: Race) -> [EngineTone] {
        let live = race.cars.prefix(EngineBank.maxVoices)
        let voiced = max(1, live.filter { $0.progress.finishedAt == nil }.count)
        let budget = 1 / Double(voiced).squareRoot()
        return live.enumerated().map { seat, car in
            guard car.progress.finishedAt == nil else {
                return EngineTone(hz: 0, duty: 0.3, gain: 0)
            }
            let speed = car.state.velocity.length
            // The measured floor: below this chain the engine bed rendered at
            // 4–9% peak and vanished under a countdown beep on a phone speaker.
            let gain = min(0.55, 0.22 + speed / 900) * budget
            return EngineTone(
                hz: EngineVoice.hz(forSpeed: speed) * EngineVoice.detune(seat: seat),
                duty: EngineVoice.duty(forSpeed: speed),
                gain: gain)
        }
    }

    /// **The skid was once here and inaudible.** Measured on a clover lap: 948
    /// of 2400 frames slip past the old 90 threshold — drifting 40% of the
    /// time — at a gain of 0.13 under an engine at 0.55. Starts earlier (a
    /// drift you can feel should be one you can hear) and sits ON the engine.
    /// Humans only: an AI's drift on the far side of the map is not feedback.
    static func skidGain(race: Race, humanCount: Int) -> Double {
        let humans = race.cars.prefix(max(1, humanCount))
        let maxSlip =
            humans.filter { $0.progress.finishedAt == nil }
            .map(\.state.slipSpeed).max() ?? 0
        return maxSlip > 55 ? min(0.34, (maxSlip - 55) / 380) : 0
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
        var bank = EngineBank()
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
                // Per-voice smoothing lives in the bank; skid smoothing here.
                smoothedSkid += (targets.skidGain - smoothedSkid) * 0.0015
                thumpEnv *= 0.9996

                // Every car's engine, summed — see `EngineBank`.
                let engine = bank.sample(targets: targets.engines, rate: sampleRate)

                let white = SoundEngine.noise(&seed)
                noiseFilter += (white - noiseFilter) * 0.12

                let sample =
                    engine * 0.5
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
