import Foundation
import SwiftUI

// MARK: - Seeded RNG

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

// MARK: - Cow Appearance

struct CowAppearance {
    let spotOffsets: [(CGFloat, CGFloat)]
    let spotSizes: [CGFloat]
    let bodyHueShift: Double
    let tailLength: CGFloat
}

// MARK: - Cow Evolution

enum CowEvolutionStage: String, Codable, CaseIterable {
    case calf, heifer, cow, bull

    init(totalYearlyCommits: Int) {
        switch totalYearlyCommits {
        case ..<10:    self = .calf
        case 10..<50:  self = .heifer
        case 50..<200: self = .cow
        default:       self = .bull
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .calf:   0.7
        case .heifer: 0.85
        case .cow:    1.0
        case .bull:   1.15
        }
    }

    var headScaleFactor: CGFloat {
        switch self {
        case .calf:   1.25
        case .heifer: 1.05
        case .cow:    1.0
        case .bull:   1.0
        }
    }

    var hasHorns: Bool { self == .bull }

    var displayName: String {
        switch self {
        case .calf:   "Calf"
        case .heifer: "Heifer"
        case .cow:    "Cow"
        case .bull:   "Bull"
        }
    }
}

// MARK: - Persisted Types

struct RepoCow: Codable, Identifiable, Hashable {
    var id: String { "\(owner)/\(name)" }
    let name: String
    let owner: String
    let url: String
    /// Base health set at scan time (before continuous decay)
    var baseHealth: Double
    var lastCommitDate: Date
    /// Legacy field kept for serialization compatibility; health is now computed from lastCommitDate
    var lastDecayDate: Date
    var position: CGPoint
    var totalYearlyCommits: Int
    var consecutiveHealthyScans: Int

    var evolutionStage: CowEvolutionStage {
        CowEvolutionStage(totalYearlyCommits: totalYearlyCommits)
    }

    var hasGoldenBell: Bool {
        consecutiveHealthyScans >= 4
    }

    // Decay rate: 2% per day = ~0.0833% per hour
    // A repo at 100 health with no commits reaches 0 in ~50 days
    private static let decayPerHour: Double = 100.0 / (50.0 * 24.0)

    /// Live health: baseHealth minus continuous decay since last commit
    var health: Double {
        let hoursSinceCommit = max(0, -lastCommitDate.timeIntervalSinceNow / 3600)
        let decayed = baseHealth - hoursSinceCommit * Self.decayPerHour
        return min(100, max(0, decayed))
    }

    // Support decoding old format where "health" was stored directly
    enum CodingKeys: String, CodingKey {
        case name, owner, url, baseHealth, lastCommitDate, lastDecayDate, position
        case totalYearlyCommits, consecutiveHealthyScans
        // Legacy key
        case health
    }

    init(name: String, owner: String, url: String, baseHealth: Double,
         lastCommitDate: Date, lastDecayDate: Date, position: CGPoint,
         totalYearlyCommits: Int = 0, consecutiveHealthyScans: Int = 0) {
        self.name = name
        self.owner = owner
        self.url = url
        self.baseHealth = baseHealth
        self.lastCommitDate = lastCommitDate
        self.lastDecayDate = lastDecayDate
        self.position = position
        self.totalYearlyCommits = totalYearlyCommits
        self.consecutiveHealthyScans = consecutiveHealthyScans
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        owner = try c.decode(String.self, forKey: .owner)
        url = try c.decode(String.self, forKey: .url)
        lastCommitDate = try c.decode(Date.self, forKey: .lastCommitDate)
        lastDecayDate = try c.decode(Date.self, forKey: .lastDecayDate)
        position = try c.decode(CGPoint.self, forKey: .position)
        // Try new key first, fall back to legacy "health"
        if let bh = try? c.decode(Double.self, forKey: .baseHealth) {
            baseHealth = bh
        } else {
            baseHealth = try c.decode(Double.self, forKey: .health)
        }
        totalYearlyCommits = try c.decodeIfPresent(Int.self, forKey: .totalYearlyCommits) ?? 0
        consecutiveHealthyScans = try c.decodeIfPresent(Int.self, forKey: .consecutiveHealthyScans) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(owner, forKey: .owner)
        try c.encode(url, forKey: .url)
        try c.encode(baseHealth, forKey: .baseHealth)
        try c.encode(lastCommitDate, forKey: .lastCommitDate)
        try c.encode(lastDecayDate, forKey: .lastDecayDate)
        try c.encode(position, forKey: .position)
        try c.encode(totalYearlyCommits, forKey: .totalYearlyCommits)
        try c.encode(consecutiveHealthyScans, forKey: .consecutiveHealthyScans)
    }

    static func == (lhs: RepoCow, rhs: RepoCow) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var appearance: CowAppearance {
        var seed: UInt64 = 5381
        for byte in id.utf8 {
            seed = ((seed << 5) &+ seed) &+ UInt64(byte)
        }
        var rng = SeededRNG(seed: seed)
        let spots: [(CGFloat, CGFloat)] = (0..<3).map { _ in
            (CGFloat.random(in: -8...8, using: &rng),
             CGFloat.random(in: -5...5, using: &rng))
        }
        let sizes: [CGFloat] = (0..<3).map { _ in
            CGFloat.random(in: 3...7, using: &rng)
        }
        let hueShift = Double.random(in: -0.08...0.08, using: &rng)
        let tail = CGFloat.random(in: 6...10, using: &rng)
        return CowAppearance(
            spotOffsets: spots,
            spotSizes: sizes,
            bodyHueShift: hueShift,
            tailLength: tail
        )
    }
}

struct FarmState: Codable {
    var cows: [RepoCow]
    var lastScanDate: Date?
    var githubUsername: String?
}

// MARK: - Health Tier

enum HealthTier: String, CaseIterable, Hashable {
    case thriving, happy, meh, sad, dead

    init(health: Double) {
        switch health {
        case 80...100: self = .thriving
        case 60..<80:  self = .happy
        case 40..<60:  self = .meh
        case 20..<40:  self = .sad
        default:       self = .dead
        }
    }

    var wanderSpeed: Double {
        switch self {
        case .thriving: 0.5
        case .happy:    0.35
        case .meh:      0.2
        case .sad:      0.1
        case .dead:     0
        }
    }

    var bodyColor: Color {
        switch self {
        case .thriving: .white
        case .happy:    Color(white: 0.92)
        case .meh:      Color(white: 0.80)
        case .sad:      Color(white: 0.65)
        case .dead:     Color(white: 0.45)
        }
    }

    var spotColor: Color {
        switch self {
        case .thriving: Color(red: 0.35, green: 0.20, blue: 0.10)
        case .happy:    Color(red: 0.40, green: 0.25, blue: 0.12).opacity(0.9)
        case .meh:      Color(white: 0.45)
        case .sad:      Color(white: 0.40)
        case .dead:     Color(white: 0.35)
        }
    }

    var tierColor: Color {
        switch self {
        case .thriving: .green
        case .happy:    .mint
        case .meh:      .yellow
        case .sad:      .orange
        case .dead:     .red
        }
    }

    /// Color for utilization percentage (usage gauges, menu bar dot)
    static func utilizationColor(for value: Double) -> Color {
        if value < 40 { return .green }
        if value < 60 { return .yellow }
        if value < 80 { return .orange }
        return .red
    }
}

// MARK: - Shared Utilities

func relativeDate(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    if days < 30 { return "\(days)d ago" }
    let months = days / 30
    return "\(months)mo ago"
}

// MARK: - gh API Response Types (transient)

struct GHRepoEntry: Decodable {
    let name: String
    let pushedAt: String
    let url: String
    let owner: GHOwner

    struct GHOwner: Decodable {
        let login: String
    }
}

struct GHCommitActivityWeek: Decodable {
    let total: Int
    let week: Int
    let days: [Int]
}

// MARK: - Errors

enum FarmError: Error, LocalizedError {
    case ghFailed(Int32)
    case ghNotFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghFailed(let code): "gh command failed with exit code \(code)"
        case .ghNotFound: "gh CLI not found. Install it with: brew install gh"
        case .decodingFailed(let msg): "Failed to decode gh response: \(msg)"
        }
    }
}
