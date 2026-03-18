XCODEPROJ = macos/ClaudeUsageBar.xcodeproj
SCHEME    = ClaudeUsageBar
APP_NAME  = Claude Usage Bar

# Resolve DerivedData build path
BUILD_DIR = $(shell xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) \
              -configuration Debug -showBuildSettings 2>/dev/null \
              | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')

.PHONY: build run clean generate

generate:
	cd macos && xcodegen generate

build:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug build -quiet

run: build
	@pkill -f "$(APP_NAME)" 2>/dev/null || true
	@open "$(BUILD_DIR)/$(APP_NAME).app"

clean:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) clean -quiet
	rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeUsageBar-*
