# Skid — command-line build/test/lint, so you never have to open Xcode.
# Run `make` (or `make help`) to list targets.

.DEFAULT_GOAL := help

.PHONY: help
help:  ## List the available commands
	@echo "Skid — available make targets:"
	@awk 'BEGIN {FS = ":.*## "} \
		/^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Inputs xcodegen reads — regenerate the project when any of these change.
PROJECT_INPUTS := project.yml \
	$(wildcard Sources/*/Info.plist) \
	$(wildcard Sources/*/*.xcstrings)

Skid.xcodeproj: $(PROJECT_INPUTS)
	@xcodegen generate

.PHONY: generate
generate: Skid.xcodeproj  ## Regenerate Skid.xcodeproj from project.yml (if stale)

.PHONY: run-iphone
run-iphone: Skid.xcodeproj  ## Build + launch on an iPhone simulator (DEVICE="SE" / "17 Pro" to pick)
	@Scripts/run-ios.sh iphone "$(DEVICE)"

.PHONY: run-ipad
run-ipad: Skid.xcodeproj  ## Build + launch on an iPad simulator (DEVICE="Air" / "13-inch" to pick)
	@Scripts/run-ios.sh ipad "$(DEVICE)"

.PHONY: build-ios
build-ios: Skid.xcodeproj  ## Build the iOS app (simulator, unsigned)
	@xcodebuild build -project Skid.xcodeproj -scheme Skid-iOS \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .build-xcode \
		CODE_SIGNING_ALLOWED=NO -quiet

.PHONY: test
test:  ## Run the package logic tests (no Xcode project needed)
	@swift test --package-path Packages/SkidCore

.PHONY: lint
lint:  ## SwiftLint + swift-format, both strict (as CI runs them)
	@swiftlint lint --strict
	@swift format lint --strict --recursive --configuration .swift-format \
		Packages/SkidCore/Sources Packages/SkidCore/Tests Sources

.PHONY: format
format:  ## Rewrite sources with swift-format
	@swift format --in-place --recursive --configuration .swift-format \
		Packages/SkidCore/Sources Packages/SkidCore/Tests Sources

.PHONY: icon
icon:  ## Regenerate the app icon from the game's own drawing code
	@swift run --package-path Packages/SkidCore skid-icon \
		"$(CURDIR)/Sources/Shared/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Skid.xcodeproj .build-xcode Packages/SkidCore/.build dist
	@echo "removed Skid.xcodeproj, .build-xcode, package .build, dist"

# --- Release lane -----------------------------------------------------------
# Cut a TestFlight build: `make release` runs preflight → publish → distribute.
# publish lands the version bump on main via an auto-merged PR and tags it;
# distribute archives/exports/uploads from that commit. UPLOAD=0 stops after
# export. Run from a clean, up-to-date main.
UPLOAD ?= 1
DIST_FLAGS := $(if $(filter 0,$(UPLOAD)),--no-upload,)

.PHONY: release
release: release-distribute  ## Cut a release to TestFlight (UPLOAD=0 to skip the upload)
	@echo "✓ release complete."

.PHONY: release-build
release-build:  ## Like `release` but stop after export (no upload)
	@$(MAKE) release UPLOAD=0

.PHONY: release-preflight
release-preflight:  ## Release step 1: verify a clean, up-to-date main
	@Scripts/release-preflight.sh

.PHONY: release-publish
release-publish: release-preflight  ## Release step 2: bump + changelog cut via auto-merged PR, tag main
	@Scripts/release-publish.sh

.PHONY: release-distribute
release-distribute: release-publish  ## Release step 3: archive/export (+ upload unless UPLOAD=0)
	@Scripts/release-distribute.sh $(DIST_FLAGS)

# Distribute is the likeliest step to fail (archive/export/upload) and is safe
# to repeat. These standalone retries have NO prereqs.
.PHONY: release-distribute-retry
release-distribute-retry:  ## Re-distribute an already-tagged release (no bump/PR/tag)
	@Scripts/release-distribute.sh $(DIST_FLAGS) --require-tag

.PHONY: release-upload
release-upload:  ## Upload the already-built dist/ package (no rebuild)
	@Scripts/release-distribute.sh --upload-only
