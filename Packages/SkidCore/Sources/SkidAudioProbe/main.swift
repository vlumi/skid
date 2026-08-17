import Foundation
import SkidCore
import SkidKit

/// **Renders the game's own engine voice to WAV files, so it can be heard.**
///
/// The simulator has no working audio here, which makes the engine the one part of the
/// game nobody could check. This runs `EngineVoice` — the *same* code the live audio
/// thread runs, not an approximation of it — across the speed range and writes the
/// result to disk, so the sound can be auditioned on anything that plays a file and
/// inspected numerically at the same time.
///
/// Development tooling, in the spirit of `skid-icon`: not part of the app.
///
///     swift run --package-path Packages/SkidCore skid-audio [outputDirectory]
let rate = 48_000.0

/// One second of the engine held at `speed`, as 16-bit mono samples.
func engineSamples(speed: Double, seconds: Double) -> [Int16] {
    let hz = EngineVoice.hz(forSpeed: speed)
    let duty = EngineVoice.duty(forSpeed: speed)
    let gain = min(0.55, 0.22 + speed / 900)
    var phase = 0.0
    var subPhase = 0.0
    var out: [Int16] = []
    out.reserveCapacity(Int(rate * seconds))
    for _ in 0..<Int(rate * seconds) {
        phase += hz / rate
        subPhase += hz * 0.5 / rate
        phase -= phase.rounded(.down)
        subPhase -= subPhase.rounded(.down)
        let sample =
            EngineVoice.sample(phase: phase, subPhase: subPhase, duty: duty)
            * gain * 0.5
        out.append(Int16(max(-1, min(1, sample)) * 32_767))
    }
    return out
}

/// A sweep from rest to flat out, which is what the engine is *for*.
func sweepSamples(seconds: Double) -> [Int16] {
    var phase = 0.0
    var subPhase = 0.0
    var out: [Int16] = []
    let total = Int(rate * seconds)
    for index in 0..<total {
        let speed = CarTuning().maxSpeed * Double(index) / Double(total)
        let hz = EngineVoice.hz(forSpeed: speed)
        let duty = EngineVoice.duty(forSpeed: speed)
        let gain = min(0.55, 0.22 + speed / 900)
        phase += hz / rate
        subPhase += hz * 0.5 / rate
        phase -= phase.rounded(.down)
        subPhase -= subPhase.rounded(.down)
        let sample =
            EngineVoice.sample(phase: phase, subPhase: subPhase, duty: duty)
            * gain * 0.5
        out.append(Int16(max(-1, min(1, sample)) * 32_767))
    }
    return out
}

/// The countdown: two blips and the higher start tone, spaced as they are heard.
///
/// Uses the game's own `BeepVoice`, so what this renders is what plays.
func beepSamples() -> [Int16] {
    var out: [Int16] = []
    for (index, hz) in [660.0, 660.0, 1320.0].enumerated() {
        var beep = BeepVoice.Playing()
        beep.start(hz: hz, gain: index == 2 ? 0.9 : 0.5, rate: rate)
        // The beep itself, then silence out to one second — the gap is what makes three
        // beeps countable rather than a warble.
        for _ in 0..<Int(rate) {
            out.append(Int16(max(-1, min(1, beep.sample(rate: rate))) * 32_767))
        }
    }
    return out
}

/// The engine at lap speed WITH a drift under it — the balance that matters, since a
/// clover lap spends 40% of its frames slipping. Filtered noise and the tanh limiter,
/// exactly as `SoundEngine` mixes them.
func driftSamples(speed: Double, slip: Double, seconds: Double) -> [Int16] {
    let hz = EngineVoice.hz(forSpeed: speed)
    let duty = EngineVoice.duty(forSpeed: speed)
    let engineGain = min(0.55, 0.22 + speed / 900)
    let skidGain = slip > 55 ? min(0.34, (slip - 55) / 380) : 0
    var phase = 0.0, subPhase = 0.0, noise = 0.0
    var seed: UInt64 = 0x9E37_79B9
    var out: [Int16] = []
    for _ in 0..<Int(rate * seconds) {
        phase += hz / rate
        subPhase += hz * 0.5 / rate
        phase -= phase.rounded(.down)
        subPhase -= subPhase.rounded(.down)
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        let white = Double(Int64(bitPattern: seed % 2000) - 1000) / 1000
        noise += (white - noise) * 0.12
        let engine = EngineVoice.sample(phase: phase, subPhase: subPhase, duty: duty)
        let mixed = engine * engineGain * 0.5 + noise * skidGain
        out.append(Int16(tanh(mixed) * 32_767))
    }
    return out
}

func writeWAV(_ samples: [Int16], to url: URL) throws {
    var data = Data()
    func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
    func append32(_ value: UInt32) {
        data.append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
    func append16(_ value: UInt16) {
        data.append(contentsOf: (0..<2).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
    let bytes = UInt32(samples.count * 2)
    append("RIFF"); append32(36 + bytes); append("WAVE")
    append("fmt "); append32(16); append16(1); append16(1)
    append32(UInt32(rate)); append32(UInt32(rate) * 2); append16(2); append16(16)
    append("data"); append32(bytes)
    for sample in samples {
        append16(UInt16(bitPattern: sample))
    }
    try data.write(to: url)
}

let directory = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1] : "/tmp/skid-audio")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let files: [(String, [Int16])] = [
    ("engine-idle", engineSamples(speed: 0, seconds: 1.5)),
    ("engine-quarter", engineSamples(speed: 130, seconds: 1.5)),
    ("engine-half", engineSamples(speed: 260, seconds: 1.5)),
    ("engine-flat-out", engineSamples(speed: CarTuning().maxSpeed, seconds: 1.5)),
    ("engine-sweep", sweepSamples(seconds: 4)),
    ("engine-lap", engineSamples(speed: 482, seconds: 1.5)),
    ("drift-lap", driftSamples(speed: 482, slip: 210, seconds: 1.5)),
    ("countdown", beepSamples()),
]
for (name, samples) in files {
    let url = directory.appendingPathComponent("\(name).wav")
    try writeWAV(samples, to: url)
    let peak = samples.map { abs(Int($0)) }.max() ?? 0
    print("\(url.path)  \(samples.count) samples  peak \(peak) (\(peak * 100 / 32_767)%)")
}
print("engine: \(EngineVoice.idleHz) Hz idle → \(EngineVoice.redlineHz) Hz flat out")
