import SwiftUI
import Charts

struct UsageChartView: View {
    @ObservedObject var historyService: UsageHistoryService
    @State private var selectedRange: TimeRange = .hour6
    @State private var hoverLocation: CGFloat?

    var body: some View {
        VStack(spacing: 8) {
            Picker("Range", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let points = historyService.downsampledPoints(for: selectedRange)

            if points.count >= 2 {
                chartView(points: points)
                    .frame(height: 140)

                HStack(spacing: 12) {
                    legendItem(color: .cyan, label: "5-Hour")
                    legendItem(color: .orange, label: "7-Day")
                    Spacer()
                    if let last = points.last {
                        Text(String(format: "%.0f%% / %.0f%%", last.pct5h * 100, last.pct7d * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title3)
                        .foregroundStyle(.quaternary)
                    Text("Not enough data yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func chartView(points: [UsageDataPoint]) -> some View {
        Chart {
            // Danger zone band
            RectangleMark(
                yStart: .value("DangerStart", 80),
                yEnd: .value("DangerEnd", 100)
            )
            .foregroundStyle(.red.opacity(0.06))

            // 5h area fill
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct5h * 100),
                    series: .value("S", "a5h")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan.opacity(0.25), .cyan.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // 7d area fill
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct7d * 100),
                    series: .value("S", "a7d")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange.opacity(0.20), .orange.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // 5h line
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct5h * 100),
                    series: .value("S", "l5h")
                )
                .foregroundStyle(.cyan)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            // 7d line
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.pct7d * 100),
                    series: .value("S", "l7d")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            // Current value dots
            if let last = points.last {
                PointMark(
                    x: .value("Time", last.timestamp),
                    y: .value("Usage", last.pct5h * 100)
                )
                .foregroundStyle(.cyan)
                .symbolSize(30)

                PointMark(
                    x: .value("Time", last.timestamp),
                    y: .value("Usage", last.pct7d * 100)
                )
                .foregroundStyle(.orange)
                .symbolSize(30)
            }

            // Hover crosshair
            if let hoverLocation, let hoverData = hoverDataPoint(at: hoverLocation, points: points) {
                RuleMark(x: .value("Hover", hoverData.timestamp))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .center) {
                        VStack(spacing: 2) {
                            Text(String(format: "5h: %.0f%%", hoverData.pct5h * 100))
                                .foregroundStyle(.cyan)
                            Text(String(format: "7d: %.0f%%", hoverData.pct7d * 100))
                                .foregroundStyle(.orange)
                        }
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.gray.opacity(0.3))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.gray.opacity(0.15))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(for: date))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(.gray.opacity(0.04))
                .border(.gray.opacity(0.1), width: 0.5)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverLocation = location.x - geo[proxy.plotFrame!].origin.x
                        case .ended:
                            hoverLocation = nil
                        }
                    }
            }
        }
    }

    private func hoverDataPoint(at x: CGFloat, points: [UsageDataPoint]) -> UsageDataPoint? {
        guard points.count >= 2 else { return nil }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let startTime = sorted.first!.timestamp.timeIntervalSince1970
        let endTime = sorted.last!.timestamp.timeIntervalSince1970
        let totalWidth: CGFloat = 280
        let fraction = max(0, min(1, Double(x) / Double(totalWidth)))
        let targetTime = startTime + (endTime - startTime) * fraction

        var closest = sorted[0]
        var minDist = abs(closest.timestamp.timeIntervalSince1970 - targetTime)
        for point in sorted {
            let dist = abs(point.timestamp.timeIntervalSince1970 - targetTime)
            if dist < minDist {
                minDist = dist
                closest = point
            }
        }
        return closest
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedRange {
        case .hour1, .hour6:
            formatter.dateFormat = "HH:mm"
        case .day1:
            formatter.dateFormat = "HH:mm"
        case .day7:
            formatter.dateFormat = "EEE"
        case .day30:
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 12, height: 3)
            Text(label)
        }
    }
}
