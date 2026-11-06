import CPaceCore
import Foundation
import XCTest
@testable import ClaudeUsageBar

@MainActor
final class RustPaceParityTests: XCTestCase {
    private func assertParity(_ points: [UsageDataPoint], current: Double,
                              now: Date, reset: Date?, calendar: Calendar,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expected = LegacyPaceReference.calculate(dataPoints: points,
                                                    currentUtilization: current,
                                                    resetDate: reset, now: now,
                                                    calendar: calendar)
        let service = PaceCoachService()
        service.recalculate(dataPoints: points, currentUtilization: current,
                            resetDate: reset, now: now, calendar: calendar)
        XCTAssertEqual(service.advisory, expected, file: file, line: line)
    }

    func testSeededUnsortedHistoriesMatchFrozenSwiftReference() {
        let now = Date(timeIntervalSince1970: 1_793_980_800.375)
        var seed: UInt64 = 0x67f4_c82d_314b_905a
        func random() -> Double {
            seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            return Double(seed >> 11) / 9_007_199_254_740_992
        }
        for zone in ["UTC", "America/New_York", "Asia/Kathmandu"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            for scenario in 0..<200 {
                let points = (0..<(scenario % 75)).map { _ in
                    UsageDataPoint(timestamp: now.addingTimeInterval((random() * 16000).rounded() - 9000),
                                   pct5h: (random() * 100).rounded() / 100,
                                   pct7d: 0.3)
                }
                let current = (random() * 100).rounded()
                let reset = scenario.isMultiple(of: 17) ? nil : now.addingTimeInterval(7200)
                assertParity(points, current: current, now: now, reset: reset, calendar: calendar)
            }
        }
    }

    func testWindowBoundaryFuturePointsAndStableResetTies() {
        let now = Date(timeIntervalSince1970: 1_793_980_800.375)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let specifications: [[(Double, Double)]] = [
            [(-7200.000001, 0.1), (-7200, 0.2), (0, 0.3)],
            [(-7200, 0.1), (-0.000001, 0.2), (0, 0.3), (1, 0.4)],
            [(-1000, 0.9), (-1000, 0.1), (0, 0.2)],
            [(-1000, 0.1), (-1000, 0.9), (0, 0.2)],
            [(0, 0.1), (0, 0.2), (0, 0.3)],
            [(-1000, 0.4), (0, 0.4000000001)],
        ]
        for specification in specifications {
            let points = specification.map {
                UsageDataPoint(timestamp: now.addingTimeInterval($0.0), pct5h: $0.1, pct7d: 0)
            }
            assertParity(points, current: 30, now: now,
                         reset: now.addingTimeInterval(7200), calendar: calendar)
        }
    }

    func testLocalHourBucketsAcrossDSTAndFractionalIntervals() {
        let parser = ISO8601DateFormatter()
        for instant in ["2026-03-08T07:05:00Z", "2026-11-01T06:30:00Z"] {
            let now = parser.date(from: instant)!.addingTimeInterval(0.1234567)
            for zone in ["UTC", "America/New_York", "Asia/Kathmandu"] {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: zone)!
                var points: [UsageDataPoint] = []
                for day in 1...4 {
                    let start = calendar.date(byAdding: .day, value: -day, to: now)!
                    points.append(UsageDataPoint(timestamp: start, pct5h: 0.20, pct7d: 0))
                    points.append(UsageDataPoint(timestamp: start.addingTimeInterval(31.0000001), pct5h: 0.20001, pct7d: 0))
                }
                points.append(UsageDataPoint(timestamp: now.addingTimeInterval(-1800.0000001), pct5h: 0.20, pct7d: 0))
                points.append(UsageDataPoint(timestamp: now, pct5h: 0.60, pct7d: 0))
                assertParity(points, current: 60, now: now,
                             reset: now.addingTimeInterval(7200), calendar: calendar)
            }
        }
    }

    func testInvalidNumericInputsProduceNoAdvisory() {
        let now = Date(timeIntervalSince1970: 1_793_980_800)
        let good = UsageDataPoint(timestamp: now, pct5h: 0.5, pct7d: 0.3)
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            let service = PaceCoachService()
            service.recalculate(dataPoints: [good, good], currentUtilization: bad,
                                resetDate: now.addingTimeInterval(7200), now: now)
            XCTAssertNil(service.advisory)
            let invalid = UsageDataPoint(timestamp: now, pct5h: bad, pct7d: 0.3)
            service.recalculate(dataPoints: [good, invalid], currentUtilization: 50,
                                resetDate: now.addingTimeInterval(7200), now: now)
            XCTAssertNil(service.advisory)
        }
    }

    func testNativeABIAndEmptyOrInvalidBuffers() {
        XCTAssertEqual(pace_core_abi_version(), 1)
        XCTAssertEqual(MemoryLayout<PaceCorePoint>.stride, 40)
        XCTAssertEqual(MemoryLayout<PaceCoreResult>.stride, 32)
        XCTAssertEqual(MemoryLayout<PaceCoreRequest>.stride, 40)
        var request = PaceCoreRequest(current: 50, now: 1000, reset: 2000,
                                      has_reset: 1, current_hour: 12, include_history: 1)
        XCTAssertEqual(pace_core_calculate(nil, 0, request).kind, PACE_CORE_NONE)
        XCTAssertEqual(pace_core_calculate(nil, 1, request).kind, PACE_CORE_INVALID)
        request.has_reset = 2
        XCTAssertEqual(pace_core_calculate(nil, 0, request).kind, PACE_CORE_INVALID)
        request.has_reset = 1
        request.include_history = 2
        XCTAssertEqual(pace_core_calculate(nil, 0, request).kind, PACE_CORE_INVALID)
    }
}
