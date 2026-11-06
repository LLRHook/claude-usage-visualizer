# Native pace calculations

`PaceCoachService.recalculate` calls the Rust pace core through `RustPaceCore`
and the checked-in `CPaceCore` C interface. There is no Swift runtime fallback.
The former Swift algorithm is retained only in the XCTest target as
`LegacyPaceReference`, frozen from commit `262ae5c` with explicit clock/calendar
inputs. SwiftUI advisories retain the same enum and display behavior.

## Calculation boundary

Swift supplies one immutable batch of timestamps, utilization fractions and
local calendar hours. Rust selects recent points, detects the last reset,
calculates the regression velocity, compares historical rates and projects the
time to the limit. No subprocess, filesystem, network, credentials or settings
access occurs in this boundary. A projection-only batch avoids all calendar-hour
conversions for missing/flat/decreasing histories. Only a positive slope requests
the full batch with local hours for historical comparison: at most two calculation
calls per update, plus the ABI-version check, never one call per point. Initial
transport contains only recent candidates, so an idle update does not allocate
or perform calendar conversion for the full historical batch.

Three date quantities are deliberately distinct in each C point. Ordering and
window checks use Foundation reference-date seconds; regression retains the old
explicit conversion to Unix seconds; adjacent historical intervals come from
`Date.timeIntervalSince`. Collapsing these into one Unix timestamp would lose
subsecond comparison/interval precision. Local-hour extraction stays with the
host calendar, including DST and non-whole-hour timezone offsets.

The Rust core preserves source order for historical pairs and uses original
position to break equal recent timestamps, matching the former stable sort.
The two-hour boundary is inclusive, future samples retain their former handling,
the last reset removes all samples through that exact source-ranked point, and
only the final five survivors feed regression. The 0.20 reset threshold and
1.5 historical-median threshold are unchanged.

Recent selection uses two linear passes and at most six temporary entries,
instead of materializing and sorting all recent points. Historical median uses
partition selection rather than fully sorting the rates. The rates buffer and
the host's C batch still scale with input size; this is not a measured claim of
lower whole-app memory or faster UI behavior.

Non-finite or unrepresentable calculation inputs produce no advisory rather
than trapping during an integer conversion. The C interface rejects a null
nonempty buffer, impossible slice size and unknown reset-presence/history-mode flags. Callers
must otherwise provide a valid aligned immutable buffer for the complete call;
no pointer is retained. The current interface is ABI version 1.

## Build and verification

`make native` builds the locked, dependency-free Rust crate and atomically copies
the host archive to ignored `macos/Native/lib/libpace_core.a`. Both SwiftPM and the
generated Xcode project import the same C header/module map and link that archive.
`make build` and `make test` include this step; direct SwiftPM/Xcode invocations
must run `make native` first. The packaged app statically contains the core.

```sh
make check-rust
make test-rust
make test
make build XCODEBUILD_FLAGS=CODE_SIGNING_ALLOWED=NO
make benchmark
```

The parity suite exercises the actual service-to-native path against the frozen
Swift reference with seeded unsorted histories, stable ties, reset/window
boundaries, fractional intervals, UTC/New York/Kathmandu and DST transitions.
ABI tests exercise the Swift-imported layouts and empty/invalid buffers. Existing
history tests use unique temporary files with automatic flushing disabled, so
the test suite does not open or modify the owner's real history.

CI installs Rust 1.93.1 and selects Xcode 26.3 on the standard macOS 15 ARM and
Intel runners. These labels are listed in GitHub's
[hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
and Xcode 26.3 is present in both the
[ARM image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)
and [Intel image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
The original `build` check remains a final gate requiring both architectures.
Local and hosted execution results belong in the change's evidence; the presence
of test code is not evidence that a run passed. Signed/notarized/universal app
distribution and live account flows require separate verification.

The benchmark includes the Swift adapter and calendar conversion, with separate
flat and rising 43,200-point synthetic histories. It checks equal outputs, warms
both paths, alternates three measured runs and prints samples/medians as
`PACE_BENCHMARK` JSON. `make benchmark` uses an optimized Swift host and the
release Rust core; the normal debug test suite records its debug-host numbers
separately. Compiler time and all real usage/account histories are excluded.
Shared CI timing is diagnostic rather than a flaky pass/fail speed threshold.
