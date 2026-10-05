export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
SIM := platform=iOS Simulator,name=iPhone 17 Pro
APP := com.kevinpostal.restroom
UDID ?= $(shell xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ {print $$3}' | head -1)

.PHONY: gen build test sim device

gen:
	xcodegen generate

build: gen
	xcodebuild -project Restroom.xcodeproj -scheme Restroom -destination "$(SIM)" -derivedDataPath build build

test: gen
	xcodebuild test -project Restroom.xcodeproj -scheme Restroom -destination "$(SIM)" -derivedDataPath build

sim: build
	xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Restroom.app
	xcrun simctl launch booted $(APP)

device: gen
	test -n "$(UDID)" || (echo "no iPhone paired; connect it and retry" && exit 1)
	xcodebuild -project Restroom.xcodeproj -scheme Restroom -destination "id=$(UDID)" -derivedDataPath build -allowProvisioningUpdates build
	xcrun devicectl device install app --device "$(UDID)" build/Build/Products/Debug-iphoneos/Restroom.app
	xcrun devicectl device process launch --terminate-existing --device "$(UDID)" $(APP)
