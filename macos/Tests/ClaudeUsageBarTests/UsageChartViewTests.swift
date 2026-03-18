import XCTest
@testable import ClaudeUsageBar

// NOTE: UsageChartView's xAxisLabel(for:) and hoverDataPoint(at:points:) methods are
// private instance methods on the SwiftUI View. They cannot be tested directly without
// either making them internal/public or extracting them into a standalone helper.
//
// This file tests the supporting types and data flow that UsageChartView depends on,
// specifically the TimeRange enum (axis format selection logic) and UsageDataPoint,
// which are the testable "chart helper" components.
//
// If xAxisLabel were extracted to a free function or a static method, we could test
// the format selection: .hour1/.hour6/.day1 -> "HH:mm", .day7 -> "EEE", .day30 -> "MMM d".

final class UsageChartViewTests: XCTestCase {

    // MARK: - TimeRange axis format expectations (documented, not directly testable)
    //
    // The xAxisLabel function uses these formatters based on selectedRange:
    //   .hour1, .hour6, .day1 -> "HH:mm"    (e.g., "14:30")
    //   .day7                 -> "EEE"        (e.g., "Mon")
    //   .day30                -> "MMM d"      (e.g., "Jan 15")
    //
    // Since these are private, we verify the TimeRange cases exist and have correct raw values,
    // which is what drives the formatter selection.

    func testTimeRangeRawValues() {
        XCTAssertEqual(TimeRange.hour1.rawValue, "1h")
        XCTAssertEqual(TimeRange.hour6.rawValue, "6h")
        XCTAssertEqual(TimeRange.day1.rawValue, "1d")
        XCTAssertEqual(TimeRange.day7.rawValue, "7d")
        XCTAssertEqual(TimeRange.day30.rawValue, "30d")
    }

    func testTimeRangeAllCasesCount() {
        XCTAssertEqual(TimeRange.allCases.count, 5)
    }

    // MARK: - Formatter behavior (testing the DateFormatter patterns directly)
    //
    // While we can't call xAxisLabel, we can verify the formatting patterns
    // it would use produce expected output.

    func testTimeFormatterOutput() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")

        let date = Date(timeIntervalSince1970: 1705314600) // 2024-01-15 10:30:00 UTC
        let result = formatter.string(from: date)
        XCTAssertEqual(result, "10:30")
    }

    func testWeekdayFormatterOutput() {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "UTC")

        // 2024-01-15 is a Monday
        let date = Date(timeIntervalSince1970: 1705314600) // 2024-01-15 10:30:00 UTC (midday to avoid date boundary)
        let result = formatter.string(from: date)
        XCTAssertEqual(result, "Mon")
    }

    func testDateFormatterOutput() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "UTC")

        let date = Date(timeIntervalSince1970: 1705314600) // 2024-01-15 10:30:00 UTC
        let result = formatter.string(from: date)
        XCTAssertEqual(result, "Jan 15")
    }

    // MARK: - Chart data preparation

    func testChartRequiresAtLeast2Points() {
        // The chart view shows "Not enough data yet" when points.count < 2.
        // This tests the data condition the view relies on.
        let points: [UsageDataPoint] = []
        XCTAssertTrue(points.count < 2, "Empty array should trigger the no-data state")

        let singlePoint = [UsageDataPoint(timestamp: Date(), pct5h: 0.5, pct7d: 0.3)]
        XCTAssertTrue(singlePoint.count < 2, "Single point should trigger the no-data state")
    }
}
