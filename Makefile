XCODEPROJ = macos/ClaudeUsageBar.xcodeproj
SCHEME    = ClaudeUsageBar
APP_NAME  = Claude Usage Bar
XCODEBUILD_FLAGS ?=

# Resolve DerivedData build path
BUILD_DIR = $(shell xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) \
              -configuration Debug -showBuildSettings 2>/dev/null \
              | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')

.PHONY: build run clean generate native test test-rust check-rust benchmark

native:
	sh scripts/build-native.sh

test-rust:
	cargo test --release --locked --manifest-path native/pace-core/Cargo.toml

check-rust:
	cargo fmt --check --manifest-path native/pace-core/Cargo.toml
	cargo clippy --locked --manifest-path native/pace-core/Cargo.toml --all-targets -- -D warnings

test: native
	swift test --package-path macos --skip-update --jobs 2 --xunit-output "$(CURDIR)/macos/.build/test-results.xml"

benchmark: native
	swift test --package-path macos --skip-update --jobs 2 --configuration release --filter RustPacePerformanceTests

generate:
	cd macos && xcodegen generate

build: native generate
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug build -quiet $(XCODEBUILD_FLAGS)

run: build
	@pkill -f "$(APP_NAME)" 2>/dev/null || true
	@open "$(BUILD_DIR)/$(APP_NAME).app"

clean:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) clean -quiet
	rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeUsageBar-*
