import SwiftUI
import ServiceManagement

struct SettingsWindowContent: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        TabView {
            GeneralSettingsView(usageService: usageService)
                .tabItem { Label("General", systemImage: "gear") }
            if appUpdater.canCheckForUpdates {
                UpdateSettingsView(appUpdater: appUpdater)
                    .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            }
        }
        .frame(width: 350, height: 200)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var usageService: UsageService
    @State private var launchAtLogin = false

    private let intervals: [(String, TimeInterval)] = [
        ("5m", 300), ("15m", 900), ("30m", 1800), ("1h", 3600)
    ]

    var body: some View {
        Form {
            Section("Polling") {
                Picker("Refresh interval", selection: $usageService.pollingInterval) {
                    ForEach(intervals, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: usageService.pollingInterval) {
                    usageService.startPolling()
                }
            }

            Section("Account") {
                if let email = usageService.accountEmail {
                    LabeledContent("Email", value: email)
                }
                if usageService.isAuthenticated {
                    Button("Sign Out") {
                        usageService.signOut()
                    }
                }
            }

            Section("Alerts") {
                Toggle("Notify at 80% usage", isOn: $usageService.alertsEnabled)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }
        }
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled // revert
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        Form {
            Button("Check for Updates") {
                appUpdater.checkForUpdates()
            }
            .disabled(!appUpdater.canCheckForUpdates)
        }
        .padding()
    }
}
