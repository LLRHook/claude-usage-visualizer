import XCTest
@testable import ClaudeUsageBar

@MainActor
final class PaceCoachServiceTests: XCTestCase {

    // MARK: - Nil advisory cases

    func testNilResetDateProducesNoAdvisory() {
        let service = PaceCoachService()
        let points = makeRecentPoints(count: 5, pct5hStart: 0.10, pct5hEnd: 0.50)
        service.recalculate(dataPoints: points, currentUtilization: 50, resetDate: nil)
        XCTAssertNil(service.advisory)
    }

    func testPastResetDateProducesNoAdvisory() {
        let service = PaceCoachService()
        let pastReset = Date().addingTimeInterval(-3600) // 1 hour ago
        let points = makeRecentPoints(count: 5, pct5hStart: 0.10, pct5hEnd: 0.50)
        service.recalculate(dataPoints: points, currentUtilization: 50, resetDate: pastReset)
        XCTAssertNil(service.advisory)
    }

    func testEmptyDataPointsProducesNoAdvisory() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(3600)
        service.recalculate(dataPoints: [], currentUtilization: 50, resetDate: futureReset)
        XCTAssertNil(service.advisory)
    }

    func testSingleDataPointProducesNoAdvisory() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(3600)
        let point = UsageDataPoint(
            timestamp: Date().addingTimeInterval(-300),
            pct5h: 0.30, pct7d: 0.20
        )
        service.recalculate(dataPoints: [point], currentUtilization: 50, resetDate: futureReset)
        XCTAssertNil(service.advisory)
    }

    // MARK: - onTrack cases

    func testOnTrackWhenVelocityIsNegative() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(7200)
        // Usage decreasing over time -> negative slope
        let points = makeRecentPoints(count: 3, pct5hStart: 0.60, pct5hEnd: 0.30)
        service.recalculate(dataPoints: points, currentUtilization: 30, resetDate: futureReset)
        if case .onTrack(let remaining) = service.advisory {
            XCTAssertEqual(remaining, 70.0, accuracy: 0.01)
        } else {
            XCTFail("Expected .onTrack but got \(String(describing: service.advisory))")
        }
    }

    func testOnTrackWhenVelocityIsZero() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(7200)
        // All points at same utilization -> zero slope
        let points = makeRecentPoints(count: 3, pct5hStart: 0.40, pct5hEnd: 0.40)
        service.recalculate(dataPoints: points, currentUtilization: 40, resetDate: futureReset)
        if case .onTrack(let remaining) = service.advisory {
            XCTAssertEqual(remaining, 60.0, accuracy: 0.01)
        } else {
            XCTFail("Expected .onTrack but got \(String(describing: service.advisory))")
        }
    }

    // MARK: - hitsLimit calculation

    func testHitsLimitWithKnownVelocity() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        // Two points: 50% -> 60% over 30 minutes = 20%/hour velocity
        let now = Date()
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-1800), pct5h: 0.50, pct7d: 0.30),
            UsageDataPoint(timestamp: now, pct5h: 0.60, pct7d: 0.35),
        ]
        // currentUtilization = 60, remaining = 40%, velocity = 20%/hr -> 2 hours to limit
        service.recalculate(dataPoints: points, currentUtilization: 60, resetDate: futureReset)
        if case .hitsLimit(let hours, let minutes) = service.advisory {
            XCTAssertEqual(hours, 2)
            XCTAssertEqual(minutes, 0)
        } else {
            XCTFail("Expected .hitsLimit but got \(String(describing: service.advisory))")
        }
    }

    func testHitsLimitPartialHour() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        let now = Date()
        // Two points: 70% -> 80% over 30 minutes = 20%/hour velocity
        // remaining = 20%, time = 20/20 = 1 hour = 1h 0m
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-1800), pct5h: 0.70, pct7d: 0.30),
            UsageDataPoint(timestamp: now, pct5h: 0.80, pct7d: 0.35),
        ]
        service.recalculate(dataPoints: points, currentUtilization: 80, resetDate: futureReset)
        if case .hitsLimit(let hours, let minutes) = service.advisory {
            XCTAssertEqual(hours, 1)
            XCTAssertEqual(minutes, 0)
        } else {
            XCTFail("Expected .hitsLimit but got \(String(describing: service.advisory))")
        }
    }

    func testHitsLimitWithNonRoundMinutes() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        let now = Date()
        // Two points: 0% -> 10% over 30 minutes = 20%/hour velocity
        // remaining = 90%, time = 90/20 = 4.5 hours = 4h 30m
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-1800), pct5h: 0.00, pct7d: 0.00),
            UsageDataPoint(timestamp: now, pct5h: 0.10, pct7d: 0.05),
        ]
        service.recalculate(dataPoints: points, currentUtilization: 10, resetDate: futureReset)
        if case .hitsLimit(let hours, let minutes) = service.advisory {
            XCTAssertEqual(hours, 4)
            XCTAssertEqual(minutes, 30)
        } else {
            XCTFail("Expected .hitsLimit but got \(String(describing: service.advisory))")
        }
    }

    // MARK: - slowDown

    func testSlowDownWhenVelocityExceedsMedian() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // Build historical data points at the same hour-of-day with moderate rates.
        // We need at least 4 consecutive-pair data points at the current hour
        // to produce >= 3 positive rates.
        var historical: [UsageDataPoint] = []
        for i in 0..<4 {
            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
            comps.hour = currentHour
            comps.minute = 0
            comps.second = 0
            let baseDate = calendar.date(from: comps)!.addingTimeInterval(Double(-7 + i) * 86400)
            // Two points per day, 10 minutes apart, rising 2% -> rate = 12%/hr
            let p1 = UsageDataPoint(timestamp: baseDate, pct5h: 0.20, pct7d: 0.10)
            let p2 = UsageDataPoint(timestamp: baseDate.addingTimeInterval(600), pct5h: 0.22, pct7d: 0.10)
            historical.append(p1)
            historical.append(p2)
        }

        // Current recent points with very high velocity (>> 1.5x median of 12%/hr = 18)
        // 20% -> 60% in 30 minutes = 80%/hr
        let recent = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-1800), pct5h: 0.20, pct7d: 0.10),
            UsageDataPoint(timestamp: now, pct5h: 0.60, pct7d: 0.15),
        ]

        let allPoints = historical + recent
        service.recalculate(dataPoints: allPoints, currentUtilization: 60, resetDate: futureReset)
        XCTAssertEqual(service.advisory, .slowDown)
    }

    func testNoSlowDownWithoutEnoughHistoricalRates() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        let now = Date()

        // Only 2 recent points, no historical data at current hour -> hourRates.count < 3
        // Should produce hitsLimit instead of slowDown
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-1800), pct5h: 0.20, pct7d: 0.10),
            UsageDataPoint(timestamp: now, pct5h: 0.60, pct7d: 0.15),
        ]
        service.recalculate(dataPoints: points, currentUtilization: 60, resetDate: futureReset)
        XCTAssertNotEqual(service.advisory, .slowDown)
        // With 80%/hr velocity and 40% remaining -> ~0.5h -> 0h 30m
        if case .hitsLimit(let hours, let minutes) = service.advisory {
            XCTAssertEqual(hours, 0)
            XCTAssertEqual(minutes, 30)
        } else {
            XCTFail("Expected .hitsLimit but got \(String(describing: service.advisory))")
        }
    }

    // MARK: - Post-reset detection

    func testPostResetDropDiscardsOldPoints() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(7200)
        let now = Date()

        // Simulate a reset: usage was high, then dropped drastically.
        // The drop is > 0.20 above current fraction.
        let points = [
            // Pre-reset points (should be discarded)
            UsageDataPoint(timestamp: now.addingTimeInterval(-3600), pct5h: 0.80, pct7d: 0.50),
            UsageDataPoint(timestamp: now.addingTimeInterval(-3000), pct5h: 0.85, pct7d: 0.52),
            // Post-reset point (only 1 remains) -> not enough -> nil
            UsageDataPoint(timestamp: now.addingTimeInterval(-600), pct5h: 0.10, pct7d: 0.15),
        ]

        // currentUtilization=10 -> currentFraction=0.10, threshold=0.30
        // Pre-reset pct5h of 0.80 and 0.85 > 0.30 -> discarded
        service.recalculate(dataPoints: points, currentUtilization: 10, resetDate: futureReset)
        XCTAssertNil(service.advisory)
    }

    func testPostResetKeepsEnoughPointsForCalculation() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        let now = Date()

        let points = [
            // Pre-reset point (discarded)
            UsageDataPoint(timestamp: now.addingTimeInterval(-5400), pct5h: 0.90, pct7d: 0.50),
            // Post-reset points (kept) - increasing usage
            UsageDataPoint(timestamp: now.addingTimeInterval(-1800), pct5h: 0.05, pct7d: 0.05),
            UsageDataPoint(timestamp: now, pct5h: 0.15, pct7d: 0.08),
        ]

        // currentFraction=0.15, threshold=0.35, pre-reset 0.90 > 0.35 -> discarded
        // 2 post-reset points remain with positive slope -> should get hitsLimit
        service.recalculate(dataPoints: points, currentUtilization: 15, resetDate: futureReset)
        XCTAssertNotNil(service.advisory)
        // Verify it's hitsLimit (not onTrack, since velocity is positive)
        if case .hitsLimit = service.advisory {
            // pass
        } else {
            XCTFail("Expected .hitsLimit but got \(String(describing: service.advisory))")
        }
    }

    // MARK: - Points outside 2-hour window are filtered

    func testPointsOutsideTwoHourWindowAreFiltered() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        let now = Date()

        // All points are older than 2 hours -> recentPoints will be empty -> < 2 -> nil
        let points = [
            UsageDataPoint(timestamp: now.addingTimeInterval(-8000), pct5h: 0.20, pct7d: 0.10),
            UsageDataPoint(timestamp: now.addingTimeInterval(-7500), pct5h: 0.40, pct7d: 0.20),
            UsageDataPoint(timestamp: now.addingTimeInterval(-7200.1), pct5h: 0.60, pct7d: 0.30),
        ]

        service.recalculate(dataPoints: points, currentUtilization: 60, resetDate: futureReset)
        XCTAssertNil(service.advisory)
    }

    // MARK: - Only last 5 recent points are used

    func testOnlyLast5RecentPointsUsed() {
        let service = PaceCoachService()
        let futureReset = Date().addingTimeInterval(86400)
        let now = Date()

        // Create 10 recent points; first 5 decreasing, last 5 increasing
        // If all 10 were used, slope might be near zero. With only last 5, slope is positive.
        var points: [UsageDataPoint] = []
        for i in 0..<5 {
            let t = now.addingTimeInterval(Double(-5400 + i * 120))
            points.append(UsageDataPoint(timestamp: t, pct5h: 0.80 - Double(i) * 0.10, pct7d: 0.10))
        }
        for i in 0..<5 {
            let t = now.addingTimeInterval(Double(-4200 + i * 120))
            points.append(UsageDataPoint(timestamp: t, pct5h: 0.30 + Double(i) * 0.10, pct7d: 0.10))
        }

        service.recalculate(dataPoints: points, currentUtilization: 70, resetDate: futureReset)
        // Last 5 points are increasing -> positive velocity -> should not be onTrack with 0 velocity
        XCTAssertNotNil(service.advisory)
    }

    // MARK: - Equatable conformance

    func testPaceAdvisoryEquatable() {
        XCTAssertEqual(PaceAdvisory.onTrack(remainingPercent: 50), PaceAdvisory.onTrack(remainingPercent: 50))
        XCTAssertNotEqual(PaceAdvisory.onTrack(remainingPercent: 50), PaceAdvisory.onTrack(remainingPercent: 60))
        XCTAssertEqual(PaceAdvisory.hitsLimit(hours: 1, minutes: 30), PaceAdvisory.hitsLimit(hours: 1, minutes: 30))
        XCTAssertNotEqual(PaceAdvisory.hitsLimit(hours: 1, minutes: 30), PaceAdvisory.hitsLimit(hours: 2, minutes: 0))
        XCTAssertEqual(PaceAdvisory.slowDown, PaceAdvisory.slowDown)
        XCTAssertNotEqual(PaceAdvisory.slowDown, PaceAdvisory.onTrack(remainingPercent: 50))
    }

    // MARK: - Helpers

    /// Creates `count` data points evenly spaced within the last hour,
    /// linearly interpolating pct5h from `pct5hStart` to `pct5hEnd`.
    private func makeRecentPoints(count: Int, pct5hStart: Double, pct5hEnd: Double) -> [UsageDataPoint] {
        let now = Date()
        let spacing: TimeInterval = 600 // 10 minutes apart
        return (0..<count).map { i in
            let fraction = count > 1 ? Double(i) / Double(count - 1) : 0
            let pct5h = pct5hStart + (pct5hEnd - pct5hStart) * fraction
            let timestamp = now.addingTimeInterval(-Double(count - 1 - i) * spacing)
            return UsageDataPoint(timestamp: timestamp, pct5h: pct5h, pct7d: 0.20)
        }
    }
}
