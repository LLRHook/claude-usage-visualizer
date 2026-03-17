import SwiftUI

enum PopoverTab: String {
    case usage, farm
}

struct PopoverView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var farmService: RepoFarmService
    @State private var selectedTab: PopoverTab = .usage
    @State private var farmExpanded = false

    private var viewWidth: CGFloat {
        (selectedTab == .farm && farmExpanded) ? 440 : 320
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(selectedTab == .farm ? "Repo Farm" : "Claude Usage")
                .font(.headline)

            if usageService.isAuthenticated {
                Picker("View", selection: $selectedTab) {
                    Text("Usage").tag(PopoverTab.usage)
                    Text("Farm").tag(PopoverTab.farm)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch selectedTab {
                case .usage:
                    authenticatedContent
                case .farm:
                    FarmSceneView(farmService: farmService, isExpanded: $farmExpanded)
                }
            } else {
                signInContent
            }
        }
        .padding()
        .frame(width: viewWidth)
        .animation(.spring(duration: 0.35), value: viewWidth)
    }

    // MARK: - Authenticated

    @ViewBuilder
    private var authenticatedContent: some View {
        if let usage = usageService.currentUsage {
            HStack(spacing: 0) {
                UsageGaugeView(
                    value: usage.fiveHour?.utilization ?? 0,
                    label: "5-Hour",
                    resetDate: usage.fiveHour?.resetDate
                )
                UsageGaugeView(
                    value: usage.sevenDay?.utilization ?? 0,
                    label: "7-Day",
                    resetDate: usage.sevenDay?.resetDate
                )
            }

            ModelBreakdownRow(
                opus: usage.sevenDayOpus,
                sonnet: usage.sevenDaySonnet
            )

            if let extra = usage.extraUsage, extra.isEnabled {
                ExtraUsageRow(extra: extra)
            }
        } else if let error = usageService.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        } else {
            ProgressView("Loading usage...")
        }

        UsageChartView(historyService: historyService)

        Divider()

        footerView
    }

    // MARK: - Sign In

    @ViewBuilder
    private var signInContent: some View {
        if usageService.isAwaitingCode {
            codeEntryView
        } else {
            VStack(spacing: 8) {
                Text("Sign in to view your usage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Sign in with Claude") {
                    usageService.startOAuthFlow()
                }
                .buttonStyle(.borderedProminent)
            }
        }

        if let error = usageService.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Divider()

        HStack {
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Code Entry

    @State private var codeInput = ""

    @ViewBuilder
    private var codeEntryView: some View {
        VStack(spacing: 8) {
            Text("Paste the code from your browser:")
                .font(.subheadline)
            TextField("code#state", text: $codeInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitCode() }
            HStack {
                Button("Cancel") {
                    usageService.isAwaitingCode = false
                    codeInput = ""
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Submit") { submitCode() }
                    .buttonStyle(.borderedProminent)
                    .disabled(codeInput.isEmpty)
            }
        }
    }

    private func submitCode() {
        let code = codeInput
        codeInput = ""
        Task { await usageService.submitOAuthCode(code) }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let updated = usageService.lastUpdated {
                Text(relativeTime(since: updated))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                Task { await usageService.fetchUsage() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Sign Out") {
                usageService.signOut()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "Updated \(seconds)s ago" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "Updated \(minutes)m \(secs)s ago"
    }
}

// MARK: - Arc Gauge

struct UsageGaugeView: View {
    let value: Double
    let label: String
    let resetDate: Date?
    @State private var fillAmount: Double = 0

    private var gaugeColor: Color {
        if value < 40 { return .green }
        if value < 60 { return .yellow }
        if value < 80 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Background track
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.gray.opacity(0.15), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Animated value fill
                Circle()
                    .trim(from: 0, to: 0.75 * min(max(fillAmount, 0), 100) / 100)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Value text
                VStack(spacing: -2) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(gaugeColor)
                    Text("%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .offset(y: -4)
            }
            .frame(width: 70, height: 55)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
                    fillAmount = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.5)) {
                    fillAmount = newValue
                }
            }

            Text(label)
                .font(.caption.weight(.medium))

            if let resetDate {
                Text(countdownText(to: resetDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func countdownText(to date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "Resetting..." }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "Resets \(days)d \(remHours)h"
        }
        return "Resets \(hours)h \(minutes)m"
    }
}

// MARK: - Model Breakdown Row

struct ModelBreakdownRow: View {
    let opus: UsageBucket?
    let sonnet: UsageBucket?

    var body: some View {
        let opusPct = opus?.utilization ?? 0
        let sonnetPct = sonnet?.utilization ?? 0
        guard opusPct > 0 || sonnetPct > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            HStack(spacing: 12) {
                modelBar(label: "Opus", pct: opusPct, color: .indigo)
                modelBar(label: "Sonnet", pct: sonnetPct, color: .teal)
            }
        )
    }

    private func modelBar(label: String, pct: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.15))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, geo.size.width * min(pct / 100, 1.0)))
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())

            Text(String(format: "%.0f%%", pct))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - Extra Usage Row

struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra Usage")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let used = extra.usedCredits, let limit = extra.monthlyLimit, limit > 0 {
                    Text(String(format: "$%.2f / $%.2f", used / 100, limit / 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let util = extra.utilization {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.gray.opacity(0.15))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .purple.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(util / 100, 1.0))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }
        }
    }
}
