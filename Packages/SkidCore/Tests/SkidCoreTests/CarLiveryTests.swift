import Testing

@testable import SkidCore

/// **The livery's arithmetic**, which is the part that can silently break.
///
/// The facing cue rests on one claim — each car's two tones are far enough apart to
/// read as two, while the field stays as separable as the palette made it — and that
/// is a measurement, not a matter of taste. Two earlier versions of the claim were
/// disproved here before this one held; `CarLivery.nose(of:)` records both.
struct CarLiveryTests {
    /// The whole facing cue in one assertion: **every car's nose differs in lightness
    /// from its tail by a usable margin**, whichever direction the pivot sent it.
    ///
    /// Deliberately not "the nose is lighter" — measuring killed that invariant. Lime
    /// (L\* 90.6) and yellow (92.8) have no room to lighten, so insisting on it gave
    /// them 1.9 and 4.3 of gap and two near-identical white noses. Sabotage: force
    /// both branches of `nose(of:)` to lighten and seats 2 and 5 fail here.
    @Test func everyCarsNoseContrastsWithItsTail() {
        for (seat, base) in CarPalette.paints.enumerated() {
            let nose = CarLivery.nose(of: base)
            let tail = CarLivery.tail(of: base)
            #expect(
                abs(nose.lab.l - tail.lab.l) > 12,
                """
                seat \(seat + 1): nose L* \(Int(nose.lab.l)) vs tail L* \(Int(tail.lab.l)) \
                — too close to read as two tones
                """)
        }
    }

    /// The two tones must be *visibly* two at race scale, or the car reads as one
    /// flat blob and the cue is decorative. ΔE 12 is the floor: below that the pair
    /// merges on a moving 20-unit sprite.
    @Test func theTwoTonesAreDistinguishableOnEveryCar() {
        for (seat, base) in CarPalette.paints.enumerated() {
            let separation = CarLivery.nose(of: base).distance(to: CarLivery.tail(of: base))
            #expect(
                separation > 12,
                "seat \(seat + 1): tones only ΔE \(Int(separation)) apart; they will merge")
        }
    }

    /// The pivot must actually fire — otherwise this is the lighten-everything design
    /// with extra words, and the bright-paint failure is one palette edit away from
    /// returning. Asserts both directions are exercised by the shipping palette.
    @Test func darkPaintsGetALighterNoseAndTheRestADarker() {
        let lighter = CarPalette.paints.filter { CarLivery.nose(of: $0).lab.l > $0.lab.l }
        let darker = CarPalette.paints.filter { CarLivery.nose(of: $0).lab.l < $0.lab.l }
        #expect(!lighter.isEmpty, "no paint gets a lighter nose")
        #expect(!darker.isEmpty, "no paint gets a darker nose; the pivot is dead code")
        #expect(lighter.count + darker.count == CarPalette.count, "a nose matched its tail")
    }

    /// **The accent must not become the identity.** A nose so far from its base that
    /// it reads as a different colour defeats the point — the base is what says
    /// *whose* car this is. Guards the shift from being cranked up.
    @Test func theNoseStaysRecognisablyTheSameCarsColour() {
        for (seat, base) in CarPalette.paints.enumerated() {
            let drift = CarLivery.nose(of: base).distance(to: base)
            #expect(
                drift < 60,
                "seat \(seat + 1): nose is ΔE \(Int(drift)) from its base — a second livery")
        }
    }

    /// A single-tone car is the same code path, not a special case.
    @Test func aZeroShiftIsSingleTone() {
        for base in CarPalette.paints {
            #expect(base.lightened(by: 0) == base)
        }
    }

    /// The derivation round-trips through Lab, so an asymmetric pair would shift
    /// every colour in the game a little. Sabotage: perturb one matrix coefficient in
    /// `from(lab:)` and this fails while nothing else visibly does.
    @Test func labRoundTripsBackToTheSamePaint() {
        for base in CarPalette.paints {
            let there = CarPalette.Paint.from(lab: base.lab)
            #expect(abs(there.red - base.red) < 0.005, "red drifted")
            #expect(abs(there.green - base.green) < 0.005, "green drifted")
            #expect(abs(there.blue - base.blue) < 0.005, "blue drifted")
        }
    }

    /// `lightened(by:)` is monotone in its delta across the whole range, negative
    /// through positive — so the pivot's two branches compose predictably and a
    /// clamp at either end cannot fold back on itself.
    @Test func lighteningIsMonotoneInBothDirections() {
        for base in CarPalette.paints {
            var previous = -Double.infinity
            for delta in stride(from: -40.0, through: 40.0, by: 5.0) {
                let shifted = base.lightened(by: delta).lab.l
                #expect(shifted >= previous - 0.5, "L* went backwards at delta \(delta)")
                previous = shifted
            }
        }
    }

    /// **Two-tone must not undo what the palette bought.** This is the sheen's
    /// mistake, pinned so it cannot recur: the *base* tones stay ≥ 24.7 apart under
    /// every vision type, because that is the colour a car is identified by.
    ///
    /// Sabotage: apply the lightening to the base rather than the nose and the field
    /// collapses, exactly as the 0.55 white wash did (ΔE 24.7 → 9.1).
    @Test func theBaseSeparationSurvivesTheLivery() {
        for vision in CarPalette.Paint.Vision.allCases {
            var worst = Double.infinity
            for i in CarPalette.paints.indices {
                for j in (i + 1)..<CarPalette.paints.count {
                    let a = CarLivery.tail(of: CarPalette.paints[i]).seen(with: vision)
                    let b = CarLivery.tail(of: CarPalette.paints[j]).seen(with: vision)
                    worst = min(worst, a.distance(to: b))
                }
            }
            #expect(worst >= 24.7, "under \(vision) the field is only ΔE \(Int(worst)) apart")
        }
    }

    /// **The noses are allowed to be confusable, and that is the design.**
    ///
    /// Measured across shifts 14…30, the worst nose *pair* never clears ΔE 9 under
    /// all four vision types (best is 8.5, at the shipping shift of 22) — because
    /// shifting nine paints in one direction necessarily crowds them. No value of
    /// `lightnessShift` fixes it, so a ΔE 12 floor on noses was an assertion the
    /// palette cannot satisfy, not a bug to tune out.
    ///
    /// It does not need to. A car is identified by its **base**, the large-area tone
    /// that holds ≥ 24.7 (`theBaseSeparationSurvivesTheLivery`); the nose says *which
    /// way this car points*, a question asked about one car at a time. Two cars with
    /// similar noses are still told apart by their bases.
    ///
    /// What must hold is the weaker claim: a nose never becomes so pale or so dark
    /// that it stops being a tone at all and collapses to shared white or black — the
    /// failure the first two designs produced (ΔE 0.6 apart). This is the guard for
    /// that, set just under the measured 8.5 so a regression toward white trips it.
    @Test func nosesNeverCollapseOntoOneAnother() {
        for vision in CarPalette.Paint.Vision.allCases {
            var worst = Double.infinity
            var pair = ""
            for i in CarPalette.paints.indices {
                for j in (i + 1)..<CarPalette.paints.count {
                    let a = CarLivery.nose(of: CarPalette.paints[i]).seen(with: vision)
                    let b = CarLivery.nose(of: CarPalette.paints[j]).seen(with: vision)
                    let d = a.distance(to: b)
                    if d < worst {
                        worst = d
                        pair = "seats \(i + 1)/\(j + 1)"
                    }
                }
            }
            #expect(worst >= 8, "under \(vision), \(pair) noses are only ΔE \(Int(worst)) apart")
        }
    }
}
