import Foundation

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }

    /// Fill in missing `resetsAt` by projecting from a prior known value.
    func reconciled(with previous: UsageResponse?) -> UsageResponse {
        UsageResponse(
            fiveHour: fiveHour?.reconciled(with: previous?.fiveHour),
            sevenDay: sevenDay?.reconciled(with: previous?.sevenDay),
            sevenDayOpus: sevenDayOpus?.reconciled(with: previous?.sevenDayOpus),
            sevenDaySonnet: sevenDaySonnet?.reconciled(with: previous?.sevenDaySonnet),
            extraUsage: extraUsage
        )
    }
}

struct UsageBucket: Codable {
    /// Utilization percentage 0-100
    let utilization: Double?
    /// ISO8601 reset timestamp
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    /// Fraction 0.0-1.0 for display
    var fraction: Double {
        (utilization ?? 0) / 100.0
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        return UsageBucket.parseISO8601(resetsAt)
    }

    func reconciled(with previous: UsageBucket?) -> UsageBucket {
        if resetsAt != nil { return self }
        return UsageBucket(utilization: utilization, resetsAt: previous?.resetsAt)
    }

    private nonisolated(unsafe) static let isoFormatterFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO8601(_ string: String) -> Date? {
        isoFormatterFrac.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }
}
