import CPaceCore
import Foundation

enum RustPaceCore {
    static func calculate(
        dataPoints: [UsageDataPoint],
        currentUtilization: Double,
        resetDate: Date?,
        now: Date,
        calendar: Calendar
    ) -> PaceAdvisory? {
        guard let resetDate, resetDate > now, dataPoints.count >= 2 else { return nil }
        guard pace_core_abi_version() == 1,
              currentUtilization.isFinite,
              now.timeIntervalSinceReferenceDate.isFinite,
              resetDate.timeIntervalSinceReferenceDate.isFinite
        else { return nil }

        // Bound the initial transport to the same inclusive two-hour window;
        // the core still owns validation/reset/selection/regression. Avoid a
        // full-history C copy and all Calendar work on the common idle path.
        let cutoff = now.addingTimeInterval(-2 * 3600)
        var points: [PaceCorePoint] = []
        for point in dataPoints {
            guard point.timestamp.timeIntervalSinceReferenceDate.isFinite,
                  point.pct5h.isFinite else { return nil }
            if point.timestamp >= cutoff {
                points.append(PaceCorePoint(timestamp: point.timestamp.timeIntervalSinceReferenceDate,
                                            regression_timestamp: point.timestamp.timeIntervalSince1970,
                                            fraction: point.pct5h, previous_interval: 0,
                                            local_hour: -1))
            }
        }
        var request = PaceCoreRequest(current: currentUtilization,
                                      now: now.timeIntervalSinceReferenceDate,
                                      reset: resetDate.timeIntervalSinceReferenceDate,
                                      has_reset: 1, current_hour: -1, include_history: 0)
        var result = points.withUnsafeBufferPointer {
            pace_core_calculate($0.baseAddress, $0.count, request)
        }
        if result.kind == PACE_CORE_NEEDS_HISTORY {
            request.current_hour = Int32(calendar.component(.hour, from: now))
            request.include_history = 1
            points = dataPoints.enumerated().map { index, point in
                PaceCorePoint(timestamp: point.timestamp.timeIntervalSinceReferenceDate,
                              regression_timestamp: point.timestamp.timeIntervalSince1970,
                              fraction: point.pct5h,
                              previous_interval: index == 0 ? 0 : point.timestamp.timeIntervalSince(dataPoints[index - 1].timestamp),
                              local_hour: Int32(calendar.component(.hour, from: point.timestamp)))
            }
            result = points.withUnsafeBufferPointer {
                pace_core_calculate($0.baseAddress, $0.count, request)
            }
        }
        switch result.kind {
        case PACE_CORE_ON_TRACK:
            return .onTrack(remainingPercent: result.remaining_percent)
        case PACE_CORE_HITS_LIMIT:
            guard let hours = Int(exactly: result.hours),
                  let minutes = Int(exactly: result.minutes) else { return nil }
            return .hitsLimit(hours: hours, minutes: minutes)
        case PACE_CORE_SLOW_DOWN:
            return .slowDown
        default:
            return nil
        }
    }
}
