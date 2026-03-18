import SwiftUI

struct CowView: View {
    let cow: RepoCow
    let facingRight: Bool
    var isGrazing: Bool = false
    var isSleeping: Bool = false
    var animationDate: Date = Date()
    @State private var isHovered = false

    private var tier: HealthTier { HealthTier(health: cow.health) }
    private var appearance: CowAppearance { cow.appearance }
    private var stage: CowEvolutionStage { cow.evolutionStage }

    private var legPhase: Double {
        guard !isGrazing, !isSleeping else { return 0 }
        let hashOffset = Double(cow.id.djb2Hash % 1000) / 1000.0 * .pi * 2
        return animationDate.timeIntervalSinceReferenceDate * .pi * 8 + hashOffset
    }

    var body: some View {
        VStack(spacing: 2) {
            if tier == .dead {
                gravestoneView
            } else {
                ZStack {
                    // Ground shadow
                    Ellipse()
                        .fill(.black.opacity(0.12))
                        .frame(width: 28 * stage.scaleFactor, height: 6 * stage.scaleFactor)
                        .blur(radius: 1)
                        .offset(y: 14)

                    cowSprite
                        .scaleEffect(stage.scaleFactor)
                        .scaleEffect(x: facingRight ? 1 : -1, y: 1)
                }
            }
            healthBar
        }
        .frame(width: 44 * stage.scaleFactor, height: 44 * stage.scaleFactor)
        .overlay(alignment: .top) {
            if isHovered {
                nameLabel
                    .offset(y: -20)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .zIndex(100)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Cow Sprite

    private var cowSprite: some View {
        ZStack {
            // Tail (opposite side from head)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.brown.opacity(0.6))
                .frame(width: 2, height: appearance.tailLength)
                .rotationEffect(.degrees(-20))
                .offset(x: -18, y: -2)

            // Legs with walking animation
            HStack(spacing: 18) {
                VStack(spacing: 12) {
                    Rectangle().fill(Color.brown.opacity(0.7)).frame(width: 4, height: 6)
                        .offset(y: sin(legPhase) * 1.5)
                    Rectangle().fill(Color.brown.opacity(0.7)).frame(width: 4, height: 6)
                        .offset(y: sin(legPhase + .pi) * 1.5)
                }
                VStack(spacing: 12) {
                    Rectangle().fill(Color.brown.opacity(0.7)).frame(width: 4, height: 6)
                        .offset(y: sin(legPhase + .pi) * 1.5)
                    Rectangle().fill(Color.brown.opacity(0.7)).frame(width: 4, height: 6)
                        .offset(y: sin(legPhase) * 1.5)
                }
            }
            .offset(y: 5)

            // Body
            RoundedRectangle(cornerRadius: 5)
                .fill(tier.bodyColor)
                .frame(width: 30, height: 18)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .overlay {
                    // Subtle body tint
                    RoundedRectangle(cornerRadius: 5)
                        .fill(appearance.bodyHueShift > 0
                              ? Color.orange.opacity(abs(appearance.bodyHueShift) + 0.02)
                              : Color.blue.opacity(abs(appearance.bodyHueShift) + 0.02))
                }
                .overlay {
                    // Unique spots per cow
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(tier.spotColor)
                                .frame(width: appearance.spotSizes[i], height: appearance.spotSizes[i])
                                .offset(x: appearance.spotOffsets[i].0, y: appearance.spotOffsets[i].1)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }

            // Head
            RoundedRectangle(cornerRadius: 4)
                .fill(tier.bodyColor)
                .frame(width: 13, height: 13)
                .shadow(color: .black.opacity(0.1), radius: 0.5, y: 0.5)
                .overlay { faceView }
                .scaleEffect(stage.headScaleFactor)
                .offset(x: 18, y: isGrazing ? -2 : -5)

            // Grazing tuft (suppressed when sleeping)
            if isGrazing && !isSleeping {
                grazingTuft
                    .offset(x: 24, y: 2)
            }

            // Sleep indicator
            if isSleeping {
                sleepIndicator
                    .offset(x: 22, y: isGrazing ? -18 : -22)
            }

            // Ears
            Ellipse()
                .fill(Color.pink.opacity(0.5))
                .frame(width: 4, height: 5)
                .offset(x: 17, y: isGrazing ? -11 : -14)
            Ellipse()
                .fill(Color.pink.opacity(0.5))
                .frame(width: 4, height: 5)
                .offset(x: 22, y: isGrazing ? -10 : -13)

            // Horns (bull only)
            if stage.hasHorns {
                Capsule()
                    .fill(Color(red: 0.95, green: 0.90, blue: 0.75))
                    .frame(width: 3, height: 7)
                    .rotationEffect(.degrees(-25))
                    .offset(x: 15, y: isGrazing ? -15 : -18)
                Capsule()
                    .fill(Color(red: 0.95, green: 0.90, blue: 0.75))
                    .frame(width: 3, height: 7)
                    .rotationEffect(.degrees(25))
                    .offset(x: 24, y: isGrazing ? -14 : -17)
            }

            // Golden bell (long-term healthy repos)
            if cow.hasGoldenBell {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 4, height: 4)
                    .shadow(color: .yellow.opacity(0.5), radius: 1)
                    .offset(x: 18, y: isGrazing ? 4 : 1)
            }
        }
        .frame(width: 44, height: 34)
    }

    // MARK: - Grazing Tuft

    private var grazingTuft: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.2, green: 0.6, blue: 0.15))
                .frame(width: 4, height: 3)
                .offset(x: -2, y: 1)
            Ellipse()
                .fill(Color(red: 0.25, green: 0.55, blue: 0.2))
                .frame(width: 3, height: 4)
                .offset(x: 2, y: -1)
        }
    }

    // MARK: - Sleep Indicator

    private var sleepIndicator: some View {
        let phase = animationDate.timeIntervalSinceReferenceDate
        let offset = sin(phase * 1.5) * 2
        return Text("z")
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .offset(y: CGFloat(offset))
    }

    // MARK: - Face

    @ViewBuilder
    private var faceView: some View {
        ZStack {
            HStack(spacing: 3) {
                eyeView
                eyeView
            }
            .offset(y: -1.5)

            mouthView
                .offset(y: 3.5)
        }
    }

    @ViewBuilder
    private var eyeView: some View {
        if isSleeping {
            // Closed eyes — short horizontal line
            Rectangle().fill(.black).frame(width: 3, height: 0.8)
        } else {
            switch tier {
            case .thriving:
                ZStack {
                    Circle().fill(.black).frame(width: 2.5, height: 2.5)
                    Circle().fill(.white).frame(width: 1, height: 1).offset(x: 0.5, y: -0.5)
                }
            case .happy:
                Circle().fill(.black).frame(width: 2.5, height: 2.5)
            case .meh:
                Circle().fill(.black).frame(width: 2.5, height: 2.5)
                    .clipShape(Rectangle().offset(y: 0.6))
            case .sad:
                VStack(spacing: 0) {
                    Rectangle().fill(.black).frame(width: 3, height: 0.6)
                        .rotationEffect(.degrees(-10))
                    Circle().fill(.black).frame(width: 2.5, height: 2.5)
                }
            case .dead:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var mouthView: some View {
        switch tier {
        case .thriving:
            SmileShape(isSmile: true)
                .stroke(.black, lineWidth: 0.8)
                .frame(width: 4, height: 2)
        case .happy, .meh:
            Rectangle().fill(.black).frame(width: 4, height: 0.6)
        case .sad:
            SmileShape(isSmile: false)
                .stroke(.black, lineWidth: 0.8)
                .frame(width: 4, height: 2)
        case .dead:
            EmptyView()
        }
    }

    // MARK: - Gravestone

    private var gravestoneView: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 6, bottomLeadingRadius: 1,
                bottomTrailingRadius: 1, topTrailingRadius: 6
            )
            .fill(Color(white: 0.35 + appearance.bodyHueShift))
            .frame(width: 24, height: 30)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 6, bottomLeadingRadius: 1,
                    bottomTrailingRadius: 1, topTrailingRadius: 6
                )
                .stroke(Color(white: 0.2), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            VStack(spacing: 1) {
                Text("RIP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                Text(String(cow.name.prefix(5)))
                    .font(.system(size: 5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .offset(y: -2)
        }
        .frame(width: 44, height: 34)
    }

    // MARK: - Health Bar

    private var healthBar: some View {
        Capsule()
            .fill(Color.black.opacity(0.2))
            .frame(width: 32, height: 5)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(healthBarColor)
                    .frame(width: max(2, 32 * cow.health / 100), height: 5)
            }
            .overlay {
                Capsule()
                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
            }
    }

    private var healthBarColor: Color { tier.tierColor }

    // MARK: - Hover Label

    private var nameLabel: some View {
        HStack(spacing: 3) {
            Text(String(cow.name.prefix(14)))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(String(format: "%.0f%%", cow.health))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(.black.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        )
    }
}

// MARK: - Cow Detail View

struct CowDetailView: View {
    let cow: RepoCow

    private var tier: HealthTier { HealthTier(health: cow.health) }
    private var stage: CowEvolutionStage { cow.evolutionStage }

    var body: some View {
        VStack(spacing: 10) {
            CowView(cow: cow, facingRight: true)
                .scaleEffect(1.5)
                .frame(width: 66, height: 66)

            Text(cow.name)
                .font(.headline)

            Text(cow.owner)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Circle().fill(tier.tierColor).frame(width: 8, height: 8)
                Text(tier.displayName)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tier.tierColor.opacity(0.15)))

            HStack(spacing: 4) {
                Text(stage.displayName)
                    .font(.caption.weight(.medium))
                Text("(\(cow.totalYearlyCommits) commits/yr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Health:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", cow.health))
                    .font(.caption.weight(.semibold))
            }

            HStack {
                Text("Last commit:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(relativeDate(cow.lastCommitDate))
                    .font(.caption)
            }

            if !cow.url.isEmpty, let url = URL(string: cow.url) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open on GitHub")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 200)
    }

}

// MARK: - Smile Shape

struct SmileShape: Shape {
    let isSmile: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isSmile {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
        }
        return path
    }
}

// MARK: - Previews

#Preview("All Tiers") {
    HStack(spacing: 16) {
        CowView(cow: RepoCow(name: "thriving-repo", owner: "test", url: "", baseHealth: 95, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero), facingRight: true)
        CowView(cow: RepoCow(name: "happy-repo", owner: "test", url: "", baseHealth: 70, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero), facingRight: false)
        CowView(cow: RepoCow(name: "meh-repo", owner: "test", url: "", baseHealth: 50, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero), facingRight: true)
        CowView(cow: RepoCow(name: "sad-repo", owner: "test", url: "", baseHealth: 30, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero), facingRight: false)
        CowView(cow: RepoCow(name: "dead-repo", owner: "test", url: "", baseHealth: 5, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero), facingRight: true)
    }
    .padding()
    .background(Color(red: 0.35, green: 0.65, blue: 0.25))
}

#Preview("Evolution Stages") {
    HStack(spacing: 20) {
        CowView(cow: RepoCow(name: "calf-repo", owner: "test", url: "", baseHealth: 80, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero, totalYearlyCommits: 5), facingRight: true)
        CowView(cow: RepoCow(name: "heifer-repo", owner: "test", url: "", baseHealth: 80, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero, totalYearlyCommits: 30), facingRight: true)
        CowView(cow: RepoCow(name: "cow-repo", owner: "test", url: "", baseHealth: 80, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero, totalYearlyCommits: 100), facingRight: true)
        CowView(cow: RepoCow(name: "bull-repo", owner: "test", url: "", baseHealth: 80, lastCommitDate: Date(), lastDecayDate: Date(), position: .zero, totalYearlyCommits: 500), facingRight: true)
    }
    .padding()
    .background(Color(red: 0.35, green: 0.65, blue: 0.25))
}
