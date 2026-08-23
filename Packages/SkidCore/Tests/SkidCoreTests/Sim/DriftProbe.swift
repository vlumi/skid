import Foundation
import XCTest

@testable import SkidCore

final class DriftProbe: XCTestCase {
    func testWorstCase() {
        // Same helper the real test uses, via its own file? Recreate the metric
        // by re-running the real test's numbers is not possible here, so just
        // report what CarState.length is for scale.
        print("PROBE car length = \(CarGeometry.length) units")
        print("PROBE old bound 4.0 = \(4.0/CarGeometry.length*100)% of a car")
        print("PROBE seen 4.24    = \(4.24/CarGeometry.length*100)% of a car")
        print("PROBE 5.0 bound    = \(5.0/CarGeometry.length*100)% of a car")
    }
}
