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

// MARK: - Persisted Types

struct RepoCow: Codable, Identifiable, Hashable {
    var id: String { "\(owner)/\(name)" }
    let name: String
    let owner: String
    let url: String
    var health: Double
    var lastCommitDate: Date
    var lastDecayDate: Date
    var position: CGPoint

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
