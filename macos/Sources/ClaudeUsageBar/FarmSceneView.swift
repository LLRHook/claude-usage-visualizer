import SwiftUI

struct FarmSceneView: View {
    @ObservedObject var farmService: RepoFarmService
    @Binding var isExpanded: Bool
    var weather: FarmWeather = FarmWeather.compute(utilization: 0)
    @State private var cowStates: [String: CowAnimState] = [:]
    @State private var selectedCow: RepoCow?
    @State private var filterTier: HealthTier?
    @State private var showListView = false
    @State private var sortOrder: RepoSortOrder = .health
    @State private var particles: [(x: CGFloat, y: CGFloat, speed: CGFloat, size: CGFloat)] = []

    private let fenceColor = Color(red: 0.55, green: 0.35, blue: 0.15)

    private let farmSize = CGSize(width: 400, height: 400)
    private var penBounds: CGRect { FarmState.penBounds }

    private var viewportWidth: CGFloat { isExpanded ? 400 : 290 }
    private var viewportHeight: CGFloat { isExpanded ? 400 : 240 }

    private var filteredCows: [RepoCow] {
        let base = filterTier == nil
            ? farmService.cows
            : farmService.cows.filter { HealthTier(health: $0.health) == filterTier }
        switch sortOrder {
        case .health:
            return base.sorted { $0.health > $1.health }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastCommit:
            return base.sorted { $0.lastCommitDate > $1.lastCommitDate }
        case .totalCommits:
            return base.sorted { $0.totalYearlyCommits > $1.totalYearlyCommits }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if farmService.cows.isEmpty && !farmService.isScanning {
                emptyState
            } else if showListView {
                repoListView
                statsBar
            } else {
                farmCanvas
                statsBar
            }

            if farmService.isScanning {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Scanning repos...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = farmService.scanError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack {
                Button {
                    Task { await farmService.scanRepos() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(farmService.isScanning ? "Scanning..." : "Scan Now")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(farmService.isScanning)

                if let lastScan = farmService.lastScanDate {
                    Text(relativeTime(since: lastScan))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Section("Filter") {
                        Button {
                            filterTier = nil
                        } label: {
                            if filterTier == nil { Label("All", systemImage: "checkmark") }
                            else { Text("All") }
                        }
                        ForEach(HealthTier.allCases, id: \.self) { tier in
                            Button {
                                filterTier = tier
                            } label: {
                                if filterTier == tier { Label(tier.displayName, systemImage: "checkmark") }
                                else { Text(tier.displayName) }
                            }
                        }
                    }
                    if showListView {
                        Section("Sort") {
                            ForEach(RepoSortOrder.allCases, id: \.self) { order in
                                Button {
                                    sortOrder = order
                                } label: {
                                    if sortOrder == order { Label(order.label, systemImage: "checkmark") }
                                    else { Text(order.label) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filterTier?.displayName ?? "Filter")
                    }
                    .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        showListView.toggle()
                    }
                } label: {
                    Image(systemName: showListView ? "circle.grid.2x2" : "list.bullet")
                        .font(.caption)
                        .frame(width: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(showListView ? "Farm View" : "List View")

                if !showListView {
                    Button {
                        withAnimation(.spring(duration: 0.35)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .frame(width: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Farm Canvas

    @ViewBuilder
    private var farmCanvas: some View {
        Group {
            if isExpanded {
                farmContent
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    farmContent
                }
            }
        }
        .frame(width: viewportWidth, height: viewportHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.spring(duration: 0.35), value: isExpanded)
        .onAppear { initAnimStates(); initParticles() }
        .onDisappear { persistPositions() }
        .popover(item: $selectedCow) { cow in
            CowDetailView(cow: cow)
        }
    }

    private var farmContent: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            Canvas { context, size in
                drawBackground(context: context, size: size)
                drawFence(context: context, size: size)
                drawParticles(context: context, size: size)
            }
            .frame(width: farmSize.width, height: farmSize.height)
            .overlay {
                ForEach(farmService.cows) { cow in
                    let state = cowStates[cow.id]
                    let pos = state?.position ?? cow.position
                    let angle = state?.angle ?? 0

                    CowView(
                        cow: cow,
                        facingRight: cos(angle) >= 0,
                        isGrazing: state?.isPaused ?? false,
                        isSleeping: weather.timeOfDay.cowsShouldSleep,
                        animationDate: timeline.date
                    )
                    .position(x: pos.x, y: pos.y)
                    .opacity(filterTier == nil || HealthTier(health: cow.health) == filterTier ? 1 : 0)
                    .onTapGesture { selectedCow = cow }
                }
            }
            .onChange(of: timeline.date) { _, now in
                updateAnimations(now: now)
            }
        }
    }

    // MARK: - Background Drawing

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        let skyHeight = size.height * 0.40
        var rng = SeededRNG(seed: 42)

        // Sky gradient (top 40%)
        let skySteps = 20
        for i in 0..<skySteps {
            let t = CGFloat(i) / CGFloat(skySteps)
            let stripH = skyHeight / CGFloat(skySteps)
            let rect = CGRect(x: 0, y: t * skyHeight, width: size.width, height: stripH + 1)
            context.fill(Path(rect), with: .color(skyBlend(Double(t))))
        }

        // Sun or moon
        drawCelestial(context: context, size: size, skyHeight: skyHeight)

        // Stars (night only)
        if weather.timeOfDay.showStars {
            var starRng = SeededRNG(seed: 77)
            for _ in 0..<40 {
                let sx = CGFloat.random(in: 5...size.width - 5, using: &starRng)
                let sy = CGFloat.random(in: 5...skyHeight - 5, using: &starRng)
                let starSize = CGFloat.random(in: 1.0...2.0, using: &starRng)
                let brightness = Double.random(in: 0.5...1.0, using: &starRng)
                context.fill(
                    Path(ellipseIn: CGRect(x: sx, y: sy, width: starSize, height: starSize)),
                    with: .color(Color.white.opacity(brightness))
                )
            }
        }

        // Clouds
        let cloudOp = weather.usageWeather.cloudOpacity
        if cloudOp > 0 {
            drawClouds(context: context, size: size, skyHeight: skyHeight, opacity: cloudOp)
        }

        // Grass fill
        context.fill(
            Path(CGRect(x: 0, y: skyHeight, width: size.width, height: size.height - skyHeight)),
            with: .color(weather.adjustedGrassColor)
        )

        // Grass tufts
        let grassBrightness = weather.usageWeather.grassBrightness * weather.timeOfDay.brightness
        let shift = weather.season.grassHueShift
        let darkGrass = Color(
            red: max(0, (0.28 + shift.r) * grassBrightness),
            green: max(0, (0.55 + shift.g) * grassBrightness),
            blue: max(0, (0.18 + shift.b) * grassBrightness)
        )
        let lightGrass = Color(
            red: min(1, (0.42 + shift.r) * grassBrightness),
            green: min(1, (0.72 + shift.g) * grassBrightness),
            blue: min(1, (0.30 + shift.b) * grassBrightness)
        )

        let grassArea = size.width * (size.height - skyHeight)
        let tuftsCount = Int(grassArea / 800)
        for _ in 0..<tuftsCount {
            let x = CGFloat.random(in: 0...size.width, using: &rng)
            let y = CGFloat.random(in: skyHeight...size.height, using: &rng)
            let dotSize = CGFloat.random(in: 2...4, using: &rng)
            let color = Bool.random(using: &rng) ? darkGrass : lightGrass
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize * 0.6)),
                with: .color(color.opacity(0.5))
            )
        }

        // Flowers / leaves depending on season
        if weather.season == .autumn {
            let leafColors = weather.season.leafColors
            for _ in 0..<12 {
                let x = CGFloat.random(in: 20...size.width - 20, using: &rng)
                let y = CGFloat.random(in: skyHeight + 10...size.height - 20, using: &rng)
                let leafSize = CGFloat.random(in: 2.0...3.5, using: &rng)
                let ci = Int.random(in: 0..<leafColors.count, using: &rng)
                let lc = leafColors[ci]
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: leafSize, height: leafSize * 0.7)),
                    with: .color(Color(red: lc.r, green: lc.g, blue: lc.b).opacity(0.7))
                )
            }
        } else {
            let flowerColors = [Color.white, Color.yellow, Color.purple]
            let flowerCount = weather.season.flowerCount
            for _ in 0..<flowerCount {
                let x = CGFloat.random(in: 20...size.width - 20, using: &rng)
                let y = CGFloat.random(in: skyHeight + 10...size.height - 20, using: &rng)
                let flowerSize = CGFloat.random(in: 1.5...2.5, using: &rng)
                let colorIdx = Int.random(in: 0..<3, using: &rng)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: flowerSize, height: flowerSize)),
                    with: .color(flowerColors[colorIdx].opacity(0.7))
                )
            }
        }

        // Dirt patches
        for _ in 0..<5 {
            let x = CGFloat.random(in: 30...size.width - 30, using: &rng)
            let y = CGFloat.random(in: skyHeight + 20...size.height - 30, using: &rng)
            let w = CGFloat.random(in: 8...15, using: &rng)
            let h = w * CGFloat.random(in: 0.4...0.7, using: &rng)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)),
                with: .color(Color(red: 0.45, green: 0.35, blue: 0.20).opacity(0.15))
            )
        }
    }

    // MARK: - Sky Helpers

    private func skyBlend(_ t: Double) -> Color {
        let top = weather.timeOfDay.skyTopColor
        let bot = weather.timeOfDay.skyBottomColor
        let dim = weather.usageWeather.grassBrightness
        let r = (top.r + (bot.r - top.r) * t) * dim
        let g = (top.g + (bot.g - top.g) * t) * dim
        let b = (top.b + (bot.b - top.b) * t) * dim
        return Color(red: min(1, max(0, r)), green: min(1, max(0, g)), blue: min(1, max(0, b)))
    }

    private func drawCelestial(context: GraphicsContext, size: CGSize, skyHeight: CGFloat) {
        let cx = size.width * 0.80
        let cy = skyHeight * 0.35
        switch weather.timeOfDay {
        case .night:
            // Moon
            context.fill(
                Path(ellipseIn: CGRect(x: cx - 10, y: cy - 10, width: 20, height: 20)),
                with: .color(Color(red: 0.9, green: 0.9, blue: 0.8).opacity(0.9))
            )
            // Dark crescent overlay
            context.fill(
                Path(ellipseIn: CGRect(x: cx - 5, y: cy - 11, width: 18, height: 18)),
                with: .color(skyBlend(0))
            )
        case .morning, .midday, .afternoon:
            // Sun
            let sunColor = weather.timeOfDay == .morning
                ? Color(red: 1.0, green: 0.85, blue: 0.5)
                : Color(red: 1.0, green: 0.95, blue: 0.6)
            context.fill(
                Path(ellipseIn: CGRect(x: cx - 12, y: cy - 12, width: 24, height: 24)),
                with: .color(sunColor.opacity(0.9))
            )
            // Glow
            context.fill(
                Path(ellipseIn: CGRect(x: cx - 18, y: cy - 18, width: 36, height: 36)),
                with: .color(sunColor.opacity(0.15))
            )
        case .evening:
            // Setting sun — lower and redder
            let sunY = skyHeight * 0.65
            context.fill(
                Path(ellipseIn: CGRect(x: cx - 14, y: sunY - 14, width: 28, height: 28)),
                with: .color(Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.85))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: cx - 22, y: sunY - 22, width: 44, height: 44)),
                with: .color(Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.1))
            )
        }
    }

    private func drawClouds(context: GraphicsContext, size: CGSize, skyHeight: CGFloat, opacity: Double) {
        var cloudRng = SeededRNG(seed: 123)
        let cloudCount = Int.random(in: 2...4, using: &cloudRng)
        let cloudColor = Color.white.opacity(opacity * 0.7)

        for _ in 0..<cloudCount {
            let cx = CGFloat.random(in: 30...size.width - 30, using: &cloudRng)
            let cy = CGFloat.random(in: 15...skyHeight * 0.7, using: &cloudRng)
            // Each cloud is 3-4 overlapping ellipses
            let blobCount = Int.random(in: 3...4, using: &cloudRng)
            for _ in 0..<blobCount {
                let bx = cx + CGFloat.random(in: -18...18, using: &cloudRng)
                let by = cy + CGFloat.random(in: -5...5, using: &cloudRng)
                let bw = CGFloat.random(in: 18...30, using: &cloudRng)
                let bh = CGFloat.random(in: 8...14, using: &cloudRng)
                context.fill(
                    Path(ellipseIn: CGRect(x: bx - bw / 2, y: by - bh / 2, width: bw, height: bh)),
                    with: .color(cloudColor)
                )
            }
        }
    }

    // MARK: - Particles

    private func drawParticles(context: GraphicsContext, size: CGSize) {
        switch weather.particleType {
        case .rain:
            for p in particles {
                var line = Path()
                line.move(to: CGPoint(x: p.x, y: p.y))
                line.addLine(to: CGPoint(x: p.x - 1, y: p.y + p.size))
                context.stroke(line, with: .color(Color(red: 0.6, green: 0.7, blue: 0.9).opacity(0.5)),
                               lineWidth: 1)
            }
        case .snow:
            for p in particles {
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - p.size / 2, y: p.y - p.size / 2,
                                           width: p.size, height: p.size)),
                    with: .color(Color.white.opacity(0.7))
                )
            }
        case .none:
            break
        }
    }

    private func initParticles() {
        switch weather.particleType {
        case .rain:
            particles = (0..<40).map { _ in
                (x: CGFloat.random(in: 0...farmSize.width),
                 y: CGFloat.random(in: 0...farmSize.height),
                 speed: CGFloat.random(in: 6...10),
                 size: CGFloat.random(in: 6...12))
            }
        case .snow:
            particles = (0..<25).map { _ in
                (x: CGFloat.random(in: 0...farmSize.width),
                 y: CGFloat.random(in: 0...farmSize.height),
                 speed: CGFloat.random(in: 1.0...2.5),
                 size: CGFloat.random(in: 2...4))
            }
        case .none:
            particles = []
        }
    }

    private func drawFence(context: GraphicsContext, size: CGSize) {
        let inset: CGFloat = 12
        let postSpacing: CGFloat = 38
        let postWidth: CGFloat = 5
        let postHeight: CGFloat = 16
        let railHeight: CGFloat = 2.5

        let left = inset
        let right = size.width - inset
        let top = inset
        let bottom = size.height - inset
        let darkFence = Color(red: 0.45, green: 0.28, blue: 0.12)

        // 1. Rails first (behind posts)
        var railPath = Path()
        railPath.addRect(CGRect(x: left, y: top + 2, width: right - left, height: railHeight))
        railPath.addRect(CGRect(x: left, y: top + 8, width: right - left, height: railHeight))
        railPath.addRect(CGRect(x: left, y: bottom - 4, width: right - left, height: railHeight))
        railPath.addRect(CGRect(x: left, y: bottom - 10, width: right - left, height: railHeight))
        railPath.addRect(CGRect(x: left, y: top, width: railHeight, height: bottom - top))
        railPath.addRect(CGRect(x: right - railHeight, y: top, width: railHeight, height: bottom - top))
        context.fill(railPath, with: .color(fenceColor.opacity(0.85)))

        // 2. Corner posts
        let corners: [(CGFloat, Bool)] = [
            (left, true), (right, true),   // top corners
            (left, false), (right, false), // bottom corners
        ]
        for (cx, isTop) in corners {
            let postY = isTop ? top - 3 : bottom - postHeight + 3
            var cornerPost = Path()
            cornerPost.addRect(CGRect(x: cx - postWidth / 2, y: postY, width: postWidth, height: postHeight))
            context.fill(cornerPost, with: .color(fenceColor))

            var capPath = Path()
            let capY = isTop ? top - 3 : bottom - 1
            capPath.addRect(CGRect(x: cx - postWidth / 2 - 0.5, y: capY, width: postWidth + 1, height: 2))
            context.fill(capPath, with: .color(darkFence))
        }

        // 3. Horizontal posts (skip corners)
        var x = left + postSpacing
        while x <= right - postSpacing / 2 {
            var postPath = Path()
            postPath.addRect(CGRect(x: x - postWidth / 2, y: top - 3, width: postWidth, height: postHeight))
            postPath.addRect(CGRect(x: x - postWidth / 2, y: bottom - postHeight + 3, width: postWidth, height: postHeight))
            context.fill(postPath, with: .color(fenceColor))

            var capPath = Path()
            capPath.addRect(CGRect(x: x - postWidth / 2 - 0.5, y: top - 3, width: postWidth + 1, height: 2))
            capPath.addRect(CGRect(x: x - postWidth / 2 - 0.5, y: bottom - 1, width: postWidth + 1, height: 2))
            context.fill(capPath, with: .color(darkFence))
            x += postSpacing
        }

        // 4. Side posts (skip corners)
        var y = top + postSpacing
        while y <= bottom - postSpacing / 2 {
            var sidePath = Path()
            sidePath.addRect(CGRect(x: left - 3, y: y - postHeight / 2, width: postWidth, height: postHeight))
            sidePath.addRect(CGRect(x: right - 2, y: y - postHeight / 2, width: postWidth, height: postHeight))
            context.fill(sidePath, with: .color(fenceColor))
            y += postSpacing
        }
    }

    // MARK: - Animation

    struct CowAnimState {
        var position: CGPoint
        var angle: Double
        var nextDirectionChange: Date
        var isPaused: Bool
        var pauseUntil: Date?
        var lastUpdate: Date
    }

    private func initAnimStates() {
        var states: [String: CowAnimState] = [:]
        let now = Date()
        let margin: CGFloat = 36
        let bounds = penBounds

        for cow in farmService.cows {
            let existing = cowStates[cow.id]
            var pos = existing?.position ?? cow.position

            if pos.x < bounds.minX + margin || pos.x > bounds.maxX - margin
                || pos.y < bounds.minY + margin || pos.y > bounds.maxY - margin
                || pos == .zero {
                pos = CGPoint(
                    x: CGFloat.random(in: bounds.minX + margin...bounds.maxX - margin),
                    y: CGFloat.random(in: bounds.minY + margin...bounds.maxY - margin)
                )
            }

            states[cow.id] = CowAnimState(
                position: pos,
                angle: existing?.angle ?? Double.random(in: 0...(.pi * 2)),
                nextDirectionChange: now.addingTimeInterval(Double.random(in: 2...5)),
                isPaused: false,
                pauseUntil: nil,
                lastUpdate: now
            )
        }
        cowStates = states
    }

    private func updateAnimations(now: Date) {
        let bounds = penBounds
        var newStates = cowStates

        for cow in farmService.cows {
            let tier = HealthTier(health: cow.health)
            guard tier != .dead else { continue }

            var state = newStates[cow.id] ?? CowAnimState(
                position: cow.position,
                angle: Double.random(in: 0...(.pi * 2)),
                nextDirectionChange: now.addingTimeInterval(Double.random(in: 2...5)),
                isPaused: false,
                pauseUntil: nil,
                lastUpdate: now
            )

            let delta = min(now.timeIntervalSince(state.lastUpdate), 0.1)
            state.lastUpdate = now

            if state.isPaused {
                if let until = state.pauseUntil, now >= until {
                    state.isPaused = false
                    state.pauseUntil = nil
                } else {
                    newStates[cow.id] = state
                    continue
                }
            }

            if now >= state.nextDirectionChange {
                if Double.random(in: 0...1) < 0.1 {
                    state.isPaused = true
                    state.pauseUntil = now.addingTimeInterval(Double.random(in: 1...3))
                    state.nextDirectionChange = (state.pauseUntil ?? now).addingTimeInterval(Double.random(in: 2...5))
                    newStates[cow.id] = state
                    continue
                }
                state.angle += Double.random(in: -.pi / 4 ... .pi / 4)
                state.nextDirectionChange = now.addingTimeInterval(Double.random(in: 2...5))
            }

            let speed = tier.wanderSpeed * 20
            let dx = cos(state.angle) * speed * delta
            let dy = sin(state.angle) * speed * delta
            var newX = state.position.x + dx
            var newY = state.position.y + dy

            let margin: CGFloat = 36
            if newX < bounds.minX + margin || newX > bounds.maxX - margin {
                state.angle = .pi - state.angle
                newX = max(bounds.minX + margin, min(bounds.maxX - margin, newX))
            }
            if newY < bounds.minY + margin || newY > bounds.maxY - margin {
                state.angle = -state.angle
                newY = max(bounds.minY + margin, min(bounds.maxY - margin, newY))
            }

            state.position = CGPoint(x: newX, y: newY)
            newStates[cow.id] = state
        }

        applySeparation(&newStates)
        cowStates = newStates
        updateParticles()
    }

    // MARK: - Particle Updates

    private func updateParticles() {
        guard !particles.isEmpty else { return }
        let w = farmSize.width
        let h = farmSize.height
        let isSnow = weather.particleType == .snow

        for i in particles.indices {
            particles[i].y += particles[i].speed
            if isSnow {
                // Horizontal drift for snow
                particles[i].x += CGFloat.random(in: -0.5...0.5)
            }
            // Reset when off-screen
            if particles[i].y > h {
                particles[i].y = -particles[i].size
                particles[i].x = CGFloat.random(in: 0...w)
            }
            // Wrap horizontal
            if particles[i].x < 0 { particles[i].x = w }
            if particles[i].x > w { particles[i].x = 0 }
        }
    }

    // MARK: - Collision Avoidance

    private func applySeparation(_ states: inout [String: CowAnimState]) {
        let cellSize: CGFloat = 50
        let minDist: CGFloat = 36
        let cols = Int(ceil(farmSize.width / cellSize))

        // Build spatial hash
        var grid: [Int: [String]] = [:]
        for (id, state) in states {
            let cx = Int(state.position.x / cellSize)
            let cy = Int(state.position.y / cellSize)
            let key = cy * cols + cx
            grid[key, default: []].append(id)
        }

        // Collect push forces
        var pushes: [String: (CGFloat, CGFloat)] = [:]
        for (id, state) in states {
            let cx = Int(state.position.x / cellSize)
            let cy = Int(state.position.y / cellSize)
            var pushX: CGFloat = 0
            var pushY: CGFloat = 0

            for dy in -1...1 {
                for dx in -1...1 {
                    let key = (cy + dy) * cols + (cx + dx)
                    guard let neighbors = grid[key] else { continue }
                    for neighborID in neighbors {
                        guard neighborID != id else { continue }
                        guard let neighbor = states[neighborID] else { continue }
                        let dist = hypot(state.position.x - neighbor.position.x,
                                         state.position.y - neighbor.position.y)
                        if dist < minDist && dist > 0.01 {
                            let overlap = minDist - dist
                            let nx = (state.position.x - neighbor.position.x) / dist
                            let ny = (state.position.y - neighbor.position.y) / dist
                            pushX += nx * overlap * 0.5
                            pushY += ny * overlap * 0.5
                        }
                    }
                }
            }

            if pushX != 0 || pushY != 0 {
                pushes[id] = (pushX, pushY)
            }
        }

        // Apply forces and re-clamp
        let margin: CGFloat = 36
        let bounds = penBounds
        for (id, push) in pushes {
            guard var state = states[id] else { continue }
            state.position.x += push.0
            state.position.y += push.1
            state.position.x = max(bounds.minX + margin, min(bounds.maxX - margin, state.position.x))
            state.position.y = max(bounds.minY + margin, min(bounds.maxY - margin, state.position.y))
            states[id] = state
        }
    }

    private func persistPositions() {
        for (id, state) in cowStates {
            farmService.updateCowPosition(id: id, position: state.position)
        }
        farmService.flushToDisk()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No repos found")
                .font(.subheadline.weight(.medium))
            Text("Make sure gh is installed and authenticated.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 120)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        let counts = Dictionary(grouping: farmService.cows) { HealthTier(health: $0.health) }
        let tierInfo: [(HealthTier, String, Color)] = [
            (.thriving, "thriving", .green),
            (.happy, "happy", .mint),
            (.meh, "meh", .yellow),
            (.sad, "sad", .orange),
            (.dead, "dead", .red),
        ]
        let avgHealth = farmService.cows.isEmpty
            ? 0.0
            : farmService.cows.reduce(0) { $0 + $1.health } / Double(farmService.cows.count)
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let activeCount = farmService.cows.filter { $0.lastCommitDate > oneWeekAgo }.count

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("\(farmService.cows.count) repos")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(String(format: "Avg: %.0f%%", avgHealth))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("\(activeCount) active this week")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tierInfo, id: \.0) { tier, label, color in
                        let n = counts[tier]?.count ?? 0
                        if n > 0 {
                            HStack(spacing: 2) {
                                Circle().fill(color).frame(width: 7, height: 7)
                                Text("\(n) \(label)")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color.opacity(0.12)))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Repo List View

    private var repoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredCows) { cow in
                    RepoListRow(cow: cow)
                        .onTapGesture { selectedCow = cow }
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .popover(item: $selectedCow) { cow in
            CowDetailView(cow: cow)
        }
    }

    // MARK: - Helpers

    private func relativeTime(since date: Date) -> String {
        "Scanned \(relativeDate(date))"
    }
}

// MARK: - Sort Order

enum RepoSortOrder: String, CaseIterable {
    case health, name, lastCommit, totalCommits

    var label: String {
        switch self {
        case .health: "Health"
        case .name: "Name"
        case .lastCommit: "Last Commit"
        case .totalCommits: "Commits"
        }
    }
}

// MARK: - Repo List Row

struct RepoListRow: View {
    let cow: RepoCow

    private var tier: HealthTier { HealthTier(health: cow.health) }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tier.tierColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(cow.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(cow.owner)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f%%", cow.health))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tier.tierColor)
                Text(relativeDate(cow.lastCommitDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Capsule()
                .fill(.gray.opacity(0.15))
                .frame(width: 36, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tier.tierColor)
                        .frame(width: max(1, 36 * cow.health / 100), height: 4)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.001))
        .contentShape(Rectangle())
    }
}
