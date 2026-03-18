import Foundation

enum PaceAdvisory: Equatable {
    case onTrack(remainingPercent: Double)
    case hitsLimit(hours: Int, minutes: Int)
    case slowDown
}

@MainActor
final class PaceCoachService: ObservableObject {
    @Published var advisory: PaceAdvisory?

    func recalculate(
        dataPoints: [UsageDataPoint],
        currentUtilization: Double,
        resetDate: Date?
    ) {
        // Edge case: resetDate must be in the future
        guard let resetDate, resetDate > Date() else {
            advisory = nil
            return
        }

        // Get recent points: last 5 within the last 2 hours
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        var recentPoints = dataPoints
            .filter { $0.timestamp >= twoHoursAgo }
            .sorted { $0.timestamp < $1.timestamp }

        // Post-reset detection: discard points before a usage drop
        // If any recent point has pct5h more than 0.20 above current, a reset occurred
        let currentFraction = currentUtilization / 100.0
        if let resetIdx = recentPoints.lastIndex(where: { $0.pct5h > currentFraction + 0.20 }) {
            // Discard everything at and before the reset point
            let startIdx = recentPoints.index(after: resetIdx)
            recentPoints = Array(recentPoints[startIdx...])
        }

        // Take last 5
        recentPoints = Array(recentPoints.suffix(5))

        // Need at least 2 points
        guard recentPoints.count >= 2 else {
            advisory = nil
            return
        }

        // Linear regression on (time, utilization%)
        // t = seconds since first point, u = pct5h * 100
        let t0 = recentPoints[0].timestamp.timeIntervalSince1970
        let n = Double(recentPoints.count)

        var sumT: Double = 0
        var sumU: Double = 0
        var sumTU: Double = 0
        var sumTT: Double = 0

        for point in recentPoints {
            let t = point.timestamp.timeIntervalSince1970 - t0
            let u = point.pct5h * 100.0
            sumT += t
            sumU += u
            sumTU += t * u
            sumTT += t * t
        }

        let denominator = n * sumTT - sumT * sumT
        guard abs(denominator) > 1e-10 else {
            advisory = .onTrack(remainingPercent: 100.0 - currentUtilization)
            return
        }

        // slope = change in utilization% per second
        let slope = (n * sumTU - sumT * sumU) / denominator
        // Convert to percent per hour
        let velocity = slope * 3600.0

        // Non-positive velocity or only 1 point: on track
        if velocity <= 0 {
            advisory = .onTrack(remainingPercent: 100.0 - currentUtilization)
            return
        }

        // Historical comparison: bucket all data points by hour-of-day
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())

        var hourRates: [Double] = []
        // dataPoints are already in chronological order from recordDataPoint
        for i in 1..<dataPoints.count {
            let prev = dataPoints[i - 1]
            let curr = dataPoints[i]
            let prevHour = calendar.component(.hour, from: prev.timestamp)
            let currHour = calendar.component(.hour, from: curr.timestamp)
            guard prevHour == currentHour && currHour == currentHour else { continue }
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let du = (curr.pct5h - prev.pct5h) * 100.0
            guard du > 0 else { continue }
            let rate = du / dt * 3600.0 // percent per hour
            hourRates.append(rate)
        }

        // Check if we should issue a slowDown advisory
        if hourRates.count >= 3 {
            let sorted = hourRates.sorted()
            let median: Double
            if sorted.count % 2 == 0 {
                median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
            } else {
                median = sorted[sorted.count / 2]
            }
            if median > 0 && velocity > 1.5 * median {
                advisory = .slowDown
                return
            }
        }

        // Project time to limit
        let remaining = 100.0 - currentUtilization
        let timeToLimitHours = remaining / velocity
        let totalMinutes = Int(timeToLimitHours * 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        advisory = .hitsLimit(hours: hours, minutes: minutes)
    }
}
