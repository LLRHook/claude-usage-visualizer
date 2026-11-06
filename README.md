# Claude Usage Bar

A native macOS menu bar app that visualizes your Claude API usage in real time.

![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-blue?logo=swift&logoColor=white)

## What It Does

Sits in your macOS menu bar and displays your Claude usage stats at a glance. Click the icon to see a detailed popover with usage charts, pace coaching, and a fun farm-themed visualization. Includes auto-updates via Sparkle.

## Features

- **Menu bar icon** with dynamic usage rendering
- **Usage charts** showing consumption over time
- **Pace coaching** to help manage usage against plan limits
- **Usage history** tracking across sessions
- **Farm scene** with repo-based farm visualization and weather model
- **Settings panel** for credential management
- **Auto-updates** via Sparkle framework
- **Mock server** for local development/testing

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.2 |
| Pace calculations | Rust 1.93.1, linked in process through a C interface |
| UI | SwiftUI |
| Platform | macOS 14+ |
| Auto-update | Sparkle 2.8.1 |
| Testing | XCTest, Rust unit tests, frozen Swift/native parity reference, Python mock server |

## Building

Install Xcode with Swift 6.2 or newer, XcodeGen and the pinned Rust toolchain.
`make build` and `make test` build the Rust archive before linking the app.
The finished app contains the native implementation and needs no Rust toolchain
or external Rust process at runtime. SwiftUI, account access and history
persistence remain Swift. See [native pace calculations](docs/native-pace-core.md)
for the interface and compatibility details.

```bash
# Generate the ignored Xcode project from macos/project.yml
make generate

# Build release
make build

# Test the native core, then the Swift app and actual native call path
make check-rust
make test-rust
make test

# Run
make run

# Clean
make clean
```

For an unsigned build check, use `make build XCODEBUILD_FLAGS=CODE_SIGNING_ALLOWED=NO`.
The native archive is built for the current host architecture; other architecture
or universal distribution artifacts need their own matching native build and
packaging verification. `CARGO_TARGET_DIR` controls the reusable Cargo cache;
the app linker receives an ignored copy in `macos/Native/lib`.

## Project Structure

```
macos/Sources/ClaudeUsageBar/
├── ClaudeUsageBarApp.swift     # App entry point
├── AppDelegate.swift           # Menu bar setup
├── MenuBarIconRenderer.swift   # Dynamic icon rendering
├── PopoverView.swift           # Main popover UI
├── UsageChartView.swift        # Usage visualization
├── UsageService.swift          # API data fetching
├── UsageModel.swift            # Usage data model
├── UsageHistoryModel.swift     # Historical tracking
├── UsageHistoryService.swift   # History persistence
├── PaceCoachService.swift      # Usage pacing logic
├── RepoFarmModel.swift         # Farm visualization model
├── RepoFarmService.swift       # Farm data service
├── FarmSceneView.swift         # Farm scene rendering
├── FarmWeatherModel.swift      # Weather effects
├── CowView.swift               # Farm cow rendering
├── SettingsView.swift          # Settings panel
├── StoredCredentials.swift     # Secure credential storage
└── AppUpdater.swift            # Sparkle auto-update
scripts/
└── mock-server.py              # Local mock API for development
```
