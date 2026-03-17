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

    private let farmFile: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/claude-usage-bar/farm.json")
    }()

    private let penBounds = CGRect(x: 20, y: 20, width: 360, height: 360)

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

    private func fetchCommitActivities(repos: [GHRepoEntry]) async -> [String: Int] {
        var results: [String: Int] = [:]

        await withTaskGroup(of: (String, Int?).self) { group in
            var launched = 0
            var repoIter = repos.makeIterator()

            // Seed 5 concurrent tasks
            for _ in 0..<5 {
                guard let repo = repoIter.next() else { break }
                launched += 1
                group.addTask { [weak self] in
                    await (repo.owner.login + "/" + repo.name,
                           self?.fetchRecentCommits(owner: repo.owner.login, name: repo.name))
                }
            }

            for await (key, count) in group {
                if let count { results[key] = count }

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

    private func fetchRecentCommits(owner: String, name: String) async -> Int? {
        do {
            let data = try await runGH([
                "api", "/repos/\(owner)/\(name)/stats/commit_activity"
            ])
            let weeks = try JSONDecoder().decode([GHCommitActivityWeek].self, from: data)
            // Sum last 4 weeks
            let recent = weeks.suffix(4).reduce(0) { $0 + $1.total }
            return recent
        } catch {
            // HTTP 202 (stats computing) or other errors — skip
            return nil
        }
    }

    private func reconcile(repos: [GHRepoEntry], activities: [String: Int]) {
        let existingByID = Dictionary(uniqueKeysWithValues: state.cows.map { ($0.id, $0) })
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso8601NoFrac = ISO8601DateFormatter()
        iso8601NoFrac.formatOptions = [.withInternetDateTime]
        let now = Date()
        var newCows: [RepoCow] = []

        for repo in repos {
            let key = "\(repo.owner.login)/\(repo.name)"
            let pushedAt = iso8601.date(from: repo.pushedAt)
                ?? iso8601NoFrac.date(from: repo.pushedAt)
                ?? now

            if var cow = existingByID[key] {
                // Update existing cow
                let recentCommits = activities[key] ?? 0
                let daysSinceDecay = max(0, Calendar.current.dateComponents([.day], from: cow.lastDecayDate, to: now).day ?? 0)
                let newHealth = min(100, max(0, cow.health + Double(recentCommits) * 20 - Double(daysSinceDecay) * 5))
                cow.health = newHealth
                cow.lastDecayDate = now
                cow.lastCommitDate = pushedAt
                newCows.append(cow)
            } else {
                // New cow
                let daysSincePush = max(0, Calendar.current.dateComponents([.day], from: pushedAt, to: now).day ?? 0)
                let health = min(100, max(0, 100 - Double(daysSincePush) * 5))
                let position = randomPosition(avoiding: newCows.map(\.position))
                let cow = RepoCow(
                    name: repo.name,
                    owner: repo.owner.login,
                    url: repo.url,
                    health: health,
                    lastCommitDate: pushedAt,
                    lastDecayDate: now,
                    position: position
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
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(FarmState.self, from: data)
        } catch {
            let backup = farmFile.deletingPathExtension().appendingPathExtension("backup.json")
            try? FileManager.default.moveItem(at: farmFile, to: backup)
            state = FarmState(cows: [])
        }
    }

    func flushToDisk() {
        state.cows = cows.isEmpty ? state.cows : cows
        do {
            let dir = farmFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
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
