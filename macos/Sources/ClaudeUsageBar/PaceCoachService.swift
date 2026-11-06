import Combine
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
        resetDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        advisory = RustPaceCore.calculate(dataPoints: dataPoints,
                                         currentUtilization: currentUtilization,
                                         resetDate: resetDate,
                                         now: now, calendar: calendar)
    }
}
