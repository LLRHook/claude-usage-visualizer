import Dispatch
import Foundation
import XCTest
@testable import ClaudeUsageBar

@MainActor
final class RustPacePerformanceTests: XCTestCase {
    @inline(never)
    private func native(_ points: [UsageDataPoint], current: Double,
                        now: Date, calendar: Calendar) -> PaceAdvisory? {
        RustPaceCore.calculate(dataPoints: points, currentUtilization: current,
                               resetDate: now.addingTimeInterval(7200), now: now,
                               calendar: calendar)
    }

    @inline(never)
    private func reference(_ points: [UsageDataPoint], current: Double,
                           now: Date, calendar: Calendar) -> PaceAdvisory? {
        LegacyPaceReference.calculate(dataPoints: points, currentUtilization: current,
                                      resetDate: now.addingTimeInterval(7200), now: now,
                                      calendar: calendar)
    }

    func testSyntheticBridgeBenchmark() throws {
        let now = Date(timeIntervalSince1970: 1_793_980_800.375)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var workloads: [[String: Any]] = []
        for rising in [false, true] {
            let count = 43_200 // One synthetic minute per sample over 30 days.
            let points = (0..<count).map { index in
                UsageDataPoint(timestamp: now.addingTimeInterval(-Double(count - 1 - index) * 60),
                               pct5h: rising ? Double(index % 300) / 375 : 0.4,
                               pct7d: 0.3)
            }
            let current = points.last!.pct5h * 100
            let expected = reference(points, current: current, now: now, calendar: calendar)
            XCTAssertEqual(native(points, current: current, now: now, calendar: calendar), expected)
            // The calls above warm both paths. Alternate measured order and
            // check every result; no timing budget is asserted on shared CI.
            var samples: [String: [Double]] = ["swift": [], "rust_bridge": []]
            for run in 0..<3 {
                let order = run.isMultiple(of: 2) ? ["swift", "rust_bridge"] : ["rust_bridge", "swift"]
                for collector in order {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let result = collector == "swift"
                        ? reference(points, current: current, now: now, calendar: calendar)
                        : native(points, current: current, now: now, calendar: calendar)
                    let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    XCTAssertEqual(result, expected)
                    samples[collector]!.append(milliseconds)
                }
            }
            workloads.append([
                "name": rising ? "rising" : "flat",
                "points": count,
                "swift_median_ms": samples["swift"]!.sorted()[1],
                "rust_bridge_median_ms": samples["rust_bridge"]!.sorted()[1],
                "samples_ms": samples,
                "outputs_equal": true,
            ])
        }
        #if DEBUG
        let hostMode = "debug"
        #else
        let hostMode = "release"
        #endif
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let report: [String: Any] = [
            "schema_version": 1, "host_mode": hostMode, "architecture": architecture,
            "scope": "synthetic pace function; includes Swift adapter, calendar conversion and native calls; compilation excluded",
            "workloads": workloads,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("PACE_BENCHMARK " + String(decoding: data, as: UTF8.self))
    }
}
