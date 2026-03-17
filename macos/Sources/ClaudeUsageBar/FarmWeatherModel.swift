import SwiftUI

// MARK: - Usage Weather

enum UsageWeather: String {
    case sunny, partlyCloudy, overcast, storm

    init(utilization: Double) {
        switch utilization {
        case ..<40:    self = .sunny
        case 40..<70:  self = .partlyCloudy
        case 70..<90:  self = .overcast
        default:       self = .storm
        }
    }

    var cloudOpacity: Double {
        switch self {
        case .sunny:        0
        case .partlyCloudy: 0.3
        case .overcast:     0.6
        case .storm:        0.9
        }
    }

    var grassBrightness: Double {
        switch self {
        case .sunny:        1.0
        case .partlyCloudy: 0.95
        case .overcast:     0.85
        case .storm:        0.75
        }
    }

    var isRaining: Bool { self == .storm }
}

// MARK: - Time of Day

enum TimeOfDay: String {
    case morning, midday, afternoon, evening, night

    init(hour: Int) {
        switch hour {
        case 6..<10:  self = .morning
        case 10..<14: self = .midday
        case 14..<18: self = .afternoon
        case 18..<21: self = .evening
        default:      self = .night
        }
    }

    /// Top and bottom sky gradient colors as (r, g, b) tuples
    var skyTopColor: (r: Double, g: Double, b: Double) {
        switch self {
        case .morning:   (0.95, 0.75, 0.50)
        case .midday:    (0.40, 0.65, 0.95)
        case .afternoon: (0.85, 0.70, 0.40)
        case .evening:   (0.55, 0.30, 0.55)
        case .night:     (0.08, 0.08, 0.18)
        }
    }

    var skyBottomColor: (r: Double, g: Double, b: Double) {
        switch self {
        case .morning:   (1.00, 0.88, 0.65)
        case .midday:    (0.65, 0.82, 1.00)
        case .afternoon: (1.00, 0.85, 0.55)
        case .evening:   (0.90, 0.50, 0.30)
        case .night:     (0.12, 0.12, 0.25)
        }
    }

    var showStars: Bool { self == .night }
    var cowsShouldSleep: Bool { self == .night }

    var brightness: Double {
        switch self {
        case .morning:   0.9
        case .midday:    1.0
        case .afternoon: 0.95
        case .evening:   0.8
        case .night:     0.6
        }
    }
}

// MARK: - Season

enum Season: String {
    case spring, summer, autumn, winter

    init(month: Int) {
        switch month {
        case 3...5:  self = .spring
        case 6...8:  self = .summer
        case 9...11: self = .autumn
        default:     self = .winter
        }
    }

    var flowerCount: Int {
        switch self {
        case .spring: 25
        case .summer: 15
        case .autumn: 0
        case .winter: 5
        }
    }

    var isSnowing: Bool { self == .winter }

    /// RGB adjustments applied to the base grass color
    var grassHueShift: (r: Double, g: Double, b: Double) {
        switch self {
        case .spring: (0.0, 0.05, 0.0)
        case .summer: (0.0, 0.0, 0.0)
        case .autumn: (0.08, -0.03, -0.05)
        case .winter: (-0.03, -0.03, 0.04)
        }
    }

    var leafColors: [(r: Double, g: Double, b: Double)] {
        switch self {
        case .autumn: [
            (0.85, 0.45, 0.15),
            (0.75, 0.30, 0.10),
            (0.90, 0.60, 0.20),
            (0.65, 0.25, 0.10),
        ]
        default: []
        }
    }
}

// MARK: - Combined Farm Weather

struct FarmWeather {
    let usageWeather: UsageWeather
    let timeOfDay: TimeOfDay
    let season: Season

    static func compute(utilization: Double) -> FarmWeather {
        let now = Calendar.current.dateComponents([.hour, .month], from: Date())
        return FarmWeather(
            usageWeather: UsageWeather(utilization: utilization),
            timeOfDay: TimeOfDay(hour: now.hour ?? 12),
            season: Season(month: now.month ?? 6)
        )
    }

    var adjustedGrassColor: Color {
        let base = (r: 0.35, g: 0.65, b: 0.25)
        let shift = season.grassHueShift
        let brightness = usageWeather.grassBrightness * timeOfDay.brightness
        return Color(
            red: min(1, max(0, (base.r + shift.r) * brightness)),
            green: min(1, max(0, (base.g + shift.g) * brightness)),
            blue: min(1, max(0, (base.b + shift.b) * brightness))
        )
    }

    var skyColors: (top: Color, bottom: Color) {
        let t = timeOfDay.skyTopColor
        let b = timeOfDay.skyBottomColor
        // Darken sky based on storm intensity
        let dim = usageWeather.grassBrightness
        return (
            top: Color(red: t.r * dim, green: t.g * dim, blue: t.b * dim),
            bottom: Color(red: b.r * dim, green: b.g * dim, blue: b.b * dim)
        )
    }

    enum ParticleType {
        case rain, snow, none
    }

    var particleType: ParticleType {
        if usageWeather.isRaining { return .rain }
        if season.isSnowing { return .snow }
        return .none
    }
}
