import Foundation
import AppKit

@MainActor
final class UsageHistoryService: ObservableObject {
    @Published private(set) var dataPoints: [UsageDataPoint] = []

    private let historyFile = AppPaths.historyFile
    private var flushTask: Task<Void, Never>?
    private var isDirty = false
    private let maxAge: TimeInterval = 30 * 24 * 3600 // 30 days

    init() {
        loadHistory()
        startPeriodicFlush()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.flushToDisk() }
        }
    }

    func recordDataPoint(pct5h: Double, pct7d: Double) {
        let point = UsageDataPoint(timestamp: Date(), pct5h: pct5h, pct7d: pct7d)
        dataPoints.append(point)
        isDirty = true
    }

    func downsampledPoints(for range: TimeRange) -> [UsageDataPoint] {
        let cutoff = Date().addingTimeInterval(-range.interval)
        let filtered = dataPoints.filter { $0.timestamp >= cutoff }
        guard filtered.count > range.targetPointCount else { return filtered }

        let bucketSize = range.interval / Double(range.targetPointCount)
        var buckets: [Int: [UsageDataPoint]] = [:]
        let start = cutoff.timeIntervalSince1970

        for point in filtered {
            let idx = Int((point.timestamp.timeIntervalSince1970 - start) / bucketSize)
            buckets[idx, default: []].append(point)
        }

        return buckets.sorted { $0.key < $1.key }.compactMap { _, points in
            guard !points.isEmpty else { return nil }
            let avg5h = points.map(\.pct5h).reduce(0, +) / Double(points.count)
            let avg7d = points.map(\.pct7d).reduce(0, +) / Double(points.count)
            let avgTime = points.map { $0.timestamp.timeIntervalSince1970 }.reduce(0, +) / Double(points.count)
            return UsageDataPoint(timestamp: Date(timeIntervalSince1970: avgTime), pct5h: avg5h, pct7d: avg7d)
        }
    }

    // MARK: - Persistence

    func loadHistory() {
        guard let data = try? Data(contentsOf: historyFile) else { return }
        do {
            var points = try JSONDecoder.iso8601Decoder.decode([UsageDataPoint].self, from: data)
            let cutoff = Date().addingTimeInterval(-maxAge)
            points.removeAll { $0.timestamp < cutoff }
            dataPoints = points
        } catch {
            // Backup corrupt file and reset
            let backup = historyFile.deletingPathExtension().appendingPathExtension("backup.json")
            try? FileManager.default.moveItem(at: historyFile, to: backup)
            dataPoints = []
        }
    }

    func flushToDisk() {
        guard isDirty else { return }
        do {
            let data = try JSONEncoder.iso8601Encoder.encode(dataPoints)
            try data.write(to: historyFile, options: .atomic)
            isDirty = false
        } catch {
            // Silently fail — next flush will retry
        }
    }

    private func startPeriodicFlush() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300)) // 5 min
                guard let self else { break }
                self.flushToDisk()
            }
        }
    }
}
