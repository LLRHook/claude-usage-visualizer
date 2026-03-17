import XCTest
@testable import ClaudeUsageBar

final class UsageModelTests: XCTestCase {
    func testDecodingFullResponse() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 42.5,
                "resets_at": "2025-01-15T10:30:00Z"
            },
            "seven_day": {
                "utilization": 78.0,
                "resets_at": "2025-01-20T00:00:00Z"
            },
            "extra_usage": {
                "is_enabled": true,
                "utilization": 25.0,
                "used_credits": 500,
                "monthly_limit": 2000
            }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(usage.fiveHour?.utilization, 42.5)
        XCTAssertEqual(usage.sevenDay?.utilization, 78.0)
        XCTAssertEqual(usage.fiveHour!.fraction, 0.425, accuracy: 0.001)
        XCTAssertEqual(usage.sevenDay!.fraction, 0.78, accuracy: 0.001)
        XCTAssertEqual(usage.extraUsage?.isEnabled, true)
        XCTAssertEqual(usage.extraUsage?.usedCredits, 500)
        XCTAssertEqual(usage.extraUsage?.monthlyLimit, 2000)
    }

    func testDecodingMinimalResponse() throws {
        let json = """
        {
            "five_hour": { "utilization": 0.0 },
            "seven_day": { "utilization": 0.0 }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(usage.fiveHour?.fraction, 0.0)
        XCTAssertNil(usage.fiveHour?.resetsAt)
        XCTAssertNil(usage.extraUsage)
    }

    func testReconciledFillsMissingResetsAt() {
        let previous = UsageResponse(
            fiveHour: UsageBucket(utilization: 30, resetsAt: "2025-01-15T10:00:00Z"),
            sevenDay: UsageBucket(utilization: 50, resetsAt: "2025-01-20T00:00:00Z"),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        let current = UsageResponse(
            fiveHour: UsageBucket(utilization: 45, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 55, resetsAt: "2025-01-21T00:00:00Z"),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        let reconciled = current.reconciled(with: previous)
        XCTAssertEqual(reconciled.fiveHour?.resetsAt, "2025-01-15T10:00:00Z")
        XCTAssertEqual(reconciled.sevenDay?.resetsAt, "2025-01-21T00:00:00Z")
    }

    func testBucketFractionClamping() {
        let bucket = UsageBucket(utilization: 100, resetsAt: nil)
        XCTAssertEqual(bucket.fraction, 1.0, accuracy: 0.001)

        let zeroBucket = UsageBucket(utilization: nil, resetsAt: nil)
        XCTAssertEqual(zeroBucket.fraction, 0.0, accuracy: 0.001)
    }

    func testISO8601Parsing() {
        let bucket1 = UsageBucket(utilization: 50, resetsAt: "2025-01-15T10:30:00Z")
        XCTAssertNotNil(bucket1.resetDate)

        let bucket2 = UsageBucket(utilization: 50, resetsAt: "2025-01-15T10:30:00.123Z")
        XCTAssertNotNil(bucket2.resetDate)
    }
}
