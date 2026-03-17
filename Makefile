.PHONY: build run clean

build:
	cd macos && swift build -c release

run:
	cd macos && swift run

clean:
	cd macos && swift package clean
