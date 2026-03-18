import Foundation
import AppKit

@MainActor
final class RepoFarmService: ObservableObject {
    @Published private(set) var cows: [RepoCow] = []
    @Published private(set) var isScanning = false
    @Published var scanError: String?
    @Published private(set) var lastScanDate: Date?

    private var state = FarmState(cows: [])
    private var pollingTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?

    private let farmFile = AppPaths.farmFile
    private let penBounds = FarmState.penBounds

    init() {
        loadState()
        migratePositionsIfNeeded()
        cows = state.cows
        lastScanDate = state.lastScanDate
        startPolling()
        startPeriodicFlush()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.flushToDisk() }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask = Task { [weak self] in
            // Initial scan
            await self?.scanRepos()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600)) // 60 min
                guard let self else { break }
                await self.scanRepos()
            }
        }
    }

    // MARK: - gh CLI

    private func runGH(_ args: [String]) async throws -> Data {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + args
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FarmError.ghFailed(process.terminationStatus)
            }
            return stdout.fileHandleForReading.readDataToEndOfFile()
        }.value
    }

    // MARK: - Scan

    func scanRepos() async {
        guard !isScanning else { return }
        isScanning = true
        scanError = nil
        defer { isScanning = false }

        do {
            // 1. Get username
            if state.githubUsername == nil {
                let userData = try await runGH(["api", "/user", "--jq", ".login"])
                if let username = String(data: userData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !username.isEmpty {
                    state.githubUsername = username
                }
            }

            // 2. List repos
            let repoData = try await runGH([
                "repo", "list",
                "--limit", "200",
                "--json", "name,pushedAt,url,owner"
            ])
            let repos = try JSONDecoder().decode([GHRepoEntry].self, from: repoData)

            // 3. Fetch commit activity per repo (batched, 5 concurrent)
            let activities = await fetchCommitActivities(repos: repos)

            // 4. Reconcile
            reconcile(repos: repos, activities: activities)

            state.lastScanDate = Date()
            lastScanDate = state.lastScanDate
            cows = state.cows
            flushToDisk()
        } catch {
            scanError = error.localizedDescription
            print("[RepoFarm] Scan error: \(error)")
        }
    }

    private func fetchCommitActivities(repos: [GHRepoEntry]) async -> [String: (recent: Int, total: Int)] {
        var results: [String: (recent: Int, total: Int)] = [:]

        await withTaskGroup(of: (String, (recent: Int, total: Int)?).self) { group in
            var repoIter = repos.makeIterator()

            // Seed 5 concurrent tasks
            for _ in 0..<5 {
                guard let repo = repoIter.next() else { break }
                group.addTask { [weak self] in
                    await (repo.owner.login + "/" + repo.name,
                           self?.fetchRecentCommits(owner: repo.owner.login, name: repo.name))
                }
            }

            for await (key, activity) in group {
                if let activity { results[key] = activity }

                if let repo = repoIter.next() {
                    group.addTask { [weak self] in
                        await (repo.owner.login + "/" + repo.name,
                               self?.fetchRecentCommits(owner: repo.owner.login, name: repo.name))
                    }
                }
            }
        }

        return results
    }

    private func fetchRecentCommits(owner: String, name: String) async -> (recent: Int, total: Int)? {
        do {
            let data = try await runGH([
                "api", "/repos/\(owner)/\(name)/stats/commit_activity"
            ])
            let weeks = try JSONDecoder().decode([GHCommitActivityWeek].self, from: data)
            // Sum last 4 weeks for recent, all weeks for total
            let recent = weeks.suffix(4).reduce(0) { $0 + $1.total }
            let total = weeks.reduce(0) { $0 + $1.total }
            return (recent: recent, total: total)
        } catch {
            // HTTP 202 (stats computing) or other errors — skip
            return nil
        }
    }

    private func reconcile(repos: [GHRepoEntry], activities: [String: (recent: Int, total: Int)]) {
        let existingByID = Dictionary(uniqueKeysWithValues: state.cows.map { ($0.id, $0) })
        let now = Date()
        var newCows: [RepoCow] = []

        for repo in repos {
            let key = "\(repo.owner.login)/\(repo.name)"
            let pushedAt = UsageBucket.parseISO8601(repo.pushedAt) ?? now
            let activity = activities[key]
            let recentCommits = activity?.recent ?? 0
            let totalCommits = activity?.total ?? 0

            if var cow = existingByID[key] {
                // Update existing cow — recompute baseHealth from commit activity
                let newBase = baseHealth(for: recentCommits)
                cow.baseHealth = max(cow.baseHealth, newBase) // never penalize on scan
                cow.lastDecayDate = now
                cow.lastCommitDate = pushedAt
                cow.totalYearlyCommits = totalCommits
                // Track consecutive healthy scans for golden bell
                if cow.health > 80 {
                    cow.consecutiveHealthyScans += 1
                } else {
                    cow.consecutiveHealthyScans = 0
                }
                newCows.append(cow)
            } else {
                // New cow — baseHealth from recent activity
                let baseHealth = baseHealth(for: recentCommits)
                let position = randomPosition(avoiding: newCows.map(\.position))
                let cow = RepoCow(
                    name: repo.name,
                    owner: repo.owner.login,
                    url: repo.url,
                    baseHealth: baseHealth,
                    lastCommitDate: pushedAt,
                    lastDecayDate: now,
                    position: position,
                    totalYearlyCommits: totalCommits,
                    consecutiveHealthyScans: 0
                )
                newCows.append(cow)
            }
        }

        state.cows = newCows
    }

    private func randomPosition(avoiding existing: [CGPoint]) -> CGPoint {
        let minDist: CGFloat = 40
        for _ in 0..<50 {
            let x = CGFloat.random(in: penBounds.minX + 20...penBounds.maxX - 20)
            let y = CGFloat.random(in: penBounds.minY + 20...penBounds.maxY - 20)
            let candidate = CGPoint(x: x, y: y)
            let tooClose = existing.contains { p in
                hypot(p.x - candidate.x, p.y - candidate.y) < minDist
            }
            if !tooClose { return candidate }
        }
        // Fallback: random position regardless
        return CGPoint(
            x: CGFloat.random(in: penBounds.minX + 20...penBounds.maxX - 20),
            y: CGFloat.random(in: penBounds.minY + 20...penBounds.maxY - 20)
        )
    }

    /// Diminishing returns: log scale for high-activity repos
    /// 1 commit → +8, 5 → +26, 10 → +35, 50 → +55
    private func baseHealth(for recentCommits: Int) -> Double {
        let boost = recentCommits > 0 ? min(60, 8.0 * log2(Double(recentCommits) + 1)) : 0.0
        return min(100, max(10, 30 + boost))
    }

    // MARK: - Position Migration

    /// Scale positions from old small pen (268x188) to new large pen (580x460)
    private func migratePositionsIfNeeded() {
        guard !state.cows.isEmpty else { return }
        // Detect old positions: if all cows are within the old pen area (~300x220)
        let maxX = state.cows.map(\.position.x).max() ?? 0
        let maxY = state.cows.map(\.position.y).max() ?? 0
        guard maxX < 320 && maxY < 250 else { return } // already migrated

        let oldPen = CGRect(x: 16, y: 16, width: 268, height: 188)
        for i in state.cows.indices {
            let pos = state.cows[i].position
            let normX = (pos.x - oldPen.minX) / oldPen.width
            let normY = (pos.y - oldPen.minY) / oldPen.height
            state.cows[i].position = CGPoint(
                x: penBounds.minX + normX * penBounds.width,
                y: penBounds.minY + normY * penBounds.height
            )
        }
    }

    // MARK: - Update positions from view

    func updateCowPosition(id: String, position: CGPoint) {
        if let idx = state.cows.firstIndex(where: { $0.id == id }) {
            state.cows[idx].position = position
        }
    }

    // MARK: - Persistence

    private func loadState() {
        guard let data = try? Data(contentsOf: farmFile) else { return }
        do {
            state = try JSONDecoder.iso8601Decoder.decode(FarmState.self, from: data)
        } catch {
            let backup = farmFile.deletingPathExtension().appendingPathExtension("backup.json")
            try? FileManager.default.moveItem(at: farmFile, to: backup)
            state = FarmState(cows: [])
        }
    }

    func flushToDisk() {
        state.cows = cows.isEmpty ? state.cows : cows
        do {
            try AppPaths.ensureConfigDir()
            let data = try JSONEncoder.iso8601Encoder.encode(state)
            try data.write(to: farmFile, options: .atomic)
        } catch {
            // Silently fail — next flush will retry
        }
    }

    private func startPeriodicFlush() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self else { break }
                self.flushToDisk()
            }
        }
    }
}
