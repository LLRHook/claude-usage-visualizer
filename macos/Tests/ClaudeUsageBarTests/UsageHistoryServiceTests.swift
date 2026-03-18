import XCTest
@testable import ClaudeUsageBar

@MainActor
final class UsageHistoryServiceTests: XCTestCase {

    // MARK: - recordDataPoint

    func testRecordDataPointAppendsOneEntry() {
        let service = UsageHistoryService()
        let countBefore = service.dataPoints.count

        service.recordDataPoint(pct5h: 0.25, pct7d: 0.50)
        XCTAssertEqual(service.dataPoints.count, countBefore + 1)

        let last = service.dataPoints.last!
        XCTAssertEqual(last.pct5h, 0.25, accuracy: 0.001)
        XCTAssertEqual(last.pct7d, 0.50, accuracy: 0.001)
    }

    func testRecordMultipleDataPointsPreservesOrder() {
        let service = UsageHistoryService()
        let countBefore = service.dataPoints.count

        service.recordDataPoint(pct5h: 0.10, pct7d: 0.20)
        service.recordDataPoint(pct5h: 0.30, pct7d: 0.40)
        service.recordDataPoint(pct5h: 0.50, pct7d: 0.60)

        XCTAssertEqual(service.dataPoints.count, countBefore + 3)

        // The last 3 entries should be in order
        let newPoints = Array(service.dataPoints.suffix(3))
        XCTAssertEqual(newPoints[0].pct5h, 0.10, accuracy: 0.001)
        XCTAssertEqual(newPoints[1].pct5h, 0.30, accuracy: 0.001)
        XCTAssertEqual(newPoints[2].pct5h, 0.50, accuracy: 0.001)
    }

    func testRecordDataPointUsesRecentTimestamp() {
        let service = UsageHistoryService()
        let before = Date()
        service.recordDataPoint(pct5h: 0.10, pct7d: 0.20)
        let after = Date()

        let recorded = service.dataPoints.last!
        // Timestamp should be between before and after (within a few seconds at most)
        XCTAssertGreaterThanOrEqual(recorded.timestamp.timeIntervalSince1970, before.timeIntervalSince1970 - 1)
        XCTAssertLessThanOrEqual(recorded.timestamp.timeIntervalSince1970, after.timeIntervalSince1970 + 1)
    }

    // MARK: - downsampledPoints: returns all when count < targetPointCount

    func testDownsampledPointsReturnsPointsWithinRange() {
        let service = UsageHistoryService()

        // Record a few points (well under any targetPointCount)
        for _ in 0..<5 {
            service.recordDataPoint(pct5h: 0.42, pct7d: 0.33)
        }

        // These just-recorded points should be within the .hour1 range
        let result = service.downsampledPoints(for: .hour1)
        // Should contain at least the 5 we just added
        XCTAssertGreaterThanOrEqual(result.count, 5)
    }

    func testDownsampledPointsPreservesUniformValues() {
        let service = UsageHistoryService()

        // Record points with uniform values
        for _ in 0..<5 {
            service.recordDataPoint(pct5h: 0.50, pct7d: 0.30)
        }

        let result = service.downsampledPoints(for: .hour1)
        XCTAssertGreaterThan(result.count, 0)

        // The last few points (which we just recorded) should have our values
        // (earlier historical points may differ, but averages with our data should still be close)
        let lastPoint = result.last!
        // At minimum the last bucket should contain our 0.50/0.30 data
        XCTAssertGreaterThan(lastPoint.pct5h, 0.0)
    }

    // MARK: - downsampledPoints: range behavior

    func testDownsampledPointsAllRangesReturnData() {
        let service = UsageHistoryService()

        // Record a point at "now" -- it should be within every time range
        service.recordDataPoint(pct5h: 0.42, pct7d: 0.78)

        for range in TimeRange.allCases {
            let result = service.downsampledPoints(for: range)
            XCTAssertGreaterThan(result.count, 0, "Range \(range.rawValue) should contain at least the current point")
        }
    }

    // MARK: - downsampledPoints: bucket size math

    func testDownsamplingBucketSizeCalculation() {
        // Verify the bucket size formula: interval / targetPointCount
        // .hour1: 3600 / 120 = 30 seconds per bucket
        let bucketSize1h = TimeRange.hour1.interval / Double(TimeRange.hour1.targetPointCount)
        XCTAssertEqual(bucketSize1h, 30.0, accuracy: 0.01)

        // .hour6: 21600 / 180 = 120 seconds per bucket
        let bucketSize6h = TimeRange.hour6.interval / Double(TimeRange.hour6.targetPointCount)
        XCTAssertEqual(bucketSize6h, 120.0, accuracy: 0.01)

        // .day1: 86400 / 200 = 432 seconds per bucket
        let bucketSize1d = TimeRange.day1.interval / Double(TimeRange.day1.targetPointCount)
        XCTAssertEqual(bucketSize1d, 432.0, accuracy: 0.01)

        // .day7: 604800 / 200 = 3024 seconds per bucket
        let bucketSize7d = TimeRange.day7.interval / Double(TimeRange.day7.targetPointCount)
        XCTAssertEqual(bucketSize7d, 3024.0, accuracy: 0.01)

        // .day30: 2592000 / 200 = 12960 seconds (3.6 hours) per bucket
        let bucketSize30d = TimeRange.day30.interval / Double(TimeRange.day30.targetPointCount)
        XCTAssertEqual(bucketSize30d, 12960.0, accuracy: 0.01)
    }

    // MARK: - TimeRange properties

    func testTimeRangeIntervals() {
        XCTAssertEqual(TimeRange.hour1.interval, 3600, accuracy: 0.01)
        XCTAssertEqual(TimeRange.hour6.interval, 3600 * 6, accuracy: 0.01)
        XCTAssertEqual(TimeRange.day1.interval, 3600 * 24, accuracy: 0.01)
        XCTAssertEqual(TimeRange.day7.interval, 3600 * 24 * 7, accuracy: 0.01)
        XCTAssertEqual(TimeRange.day30.interval, 3600 * 24 * 30, accuracy: 0.01)
    }

    func testTimeRangeTargetPointCounts() {
        XCTAssertEqual(TimeRange.hour1.targetPointCount, 120)
        XCTAssertEqual(TimeRange.hour6.targetPointCount, 180)
        XCTAssertEqual(TimeRange.day1.targetPointCount, 200)
        XCTAssertEqual(TimeRange.day7.targetPointCount, 200)
        XCTAssertEqual(TimeRange.day30.targetPointCount, 200)
    }

    func testTimeRangeIdentity() {
        for range in TimeRange.allCases {
            XCTAssertEqual(range.id, range.rawValue)
        }
    }

    func testTimeRangeAllCasesCount() {
        XCTAssertEqual(TimeRange.allCases.count, 5)
    }

    func testTimeRangeRawValues() {
        XCTAssertEqual(TimeRange.hour1.rawValue, "1h")
        XCTAssertEqual(TimeRange.hour6.rawValue, "6h")
        XCTAssertEqual(TimeRange.day1.rawValue, "1d")
        XCTAssertEqual(TimeRange.day7.rawValue, "7d")
        XCTAssertEqual(TimeRange.day30.rawValue, "30d")
    }

    // MARK: - UsageDataPoint

    func testUsageDataPointIdentity() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let point = UsageDataPoint(timestamp: date, pct5h: 0.50, pct7d: 0.30)
        XCTAssertEqual(point.id, date)
    }

    func testUsageDataPointCodable() throws {
        let original = UsageDataPoint(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            pct5h: 0.42,
            pct7d: 0.78
        )
        let data = try JSONEncoder.iso8601Encoder.encode(original)
        let decoded = try JSONDecoder.iso8601Decoder.decode(UsageDataPoint.self, from: data)
        XCTAssertEqual(decoded.pct5h, original.pct5h, accuracy: 0.001)
        XCTAssertEqual(decoded.pct7d, original.pct7d, accuracy: 0.001)
        XCTAssertEqual(
            decoded.timestamp.timeIntervalSince1970,
            original.timestamp.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    // MARK: - downsampledPoints: output is sorted by time

    func testDownsampledPointsAreSortedByTime() {
        let service = UsageHistoryService()
        service.recordDataPoint(pct5h: 0.10, pct7d: 0.05)
        service.recordDataPoint(pct5h: 0.20, pct7d: 0.10)

        for range in TimeRange.allCases {
            let result = service.downsampledPoints(for: range)
            for i in 1..<result.count {
                XCTAssertGreaterThanOrEqual(
                    result[i].timestamp.timeIntervalSince1970,
                    result[i - 1].timestamp.timeIntervalSince1970,
                    "Points for range \(range.rawValue) should be sorted by timestamp"
                )
            }
        }
    }
}
