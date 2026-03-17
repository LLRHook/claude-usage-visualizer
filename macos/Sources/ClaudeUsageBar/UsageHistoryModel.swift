import Foundation

struct UsageDataPoint: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    /// 5-hour utilization as fraction 0.0-1.0
    let pct5h: Double
    /// 7-day utilization as fraction 0.0-1.0
    let pct7d: Double
}

enum TimeRange: String, CaseIterable, Identifiable {
    case hour1 = "1h"
    case hour6 = "6h"
    case day1 = "1d"
    case day7 = "7d"
    case day30 = "30d"

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .hour1: 3600
        case .hour6: 3600 * 6
        case .day1: 3600 * 24
        case .day7: 3600 * 24 * 7
        case .day30: 3600 * 24 * 30
        }
    }

    var targetPointCount: Int {
        switch self {
        case .hour1: 120
        case .hour6: 180
        case .day1: 200
        case .day7: 200
        case .day30: 200
        }
    }
}
