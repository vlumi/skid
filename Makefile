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
	@Scripts/generate.sh

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

.PHONY: tracks-lint
tracks-lint:  ## Validate the bundled track designs
	@swift run --package-path Packages/SkidCore skid-tracks lint

.PHONY: tracks-export
tracks-export:  ## Re-encode the bundled track designs canonically
	@swift run --package-path Packages/SkidCore skid-tracks export \
		"$(CURDIR)/Packages/SkidCore/Sources/SkidCore/Resources/Tracks"

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Skid.xcodeproj .build-xcode Packages/SkidCore/.build dist
	@echo "removed Skid.xcodeproj, .build-xcode, package .build, dist"

# --- Release lane -----------------------------------------------------------
# Cut a build: `make release` runs preflight → publish → tag → distribute.
# Each step is its own script, re-deriving its inputs from git + project.yml,
# so any one can be re-run standalone (e.g. Scripts/release-tag.sh ios) after
# a stall. Mirrors donpa's lane.
#
# PLATFORM selects scope (default ios; macos/all reserved for a Mac target).
# UPLOAD=0 stops after export (no ASC upload).
PLATFORM ?= ios
UPLOAD ?= 1
DIST_FLAGS := $(if $(filter 0,$(UPLOAD)),--no-upload,)

.PHONY: release
release: release-distribute  ## Cut a release (PLATFORM=ios|macos|all, UPLOAD=0 to skip ASC)
	@echo "✓ release complete (PLATFORM=$(PLATFORM))."

.PHONY: release-build
release-build:  ## Like `release` but stop after export (no upload)
	@$(MAKE) release UPLOAD=0

.PHONY: release-preflight
release-preflight:  ## Release step 1: verify a clean, up-to-date base (main or release/X.Y.x)
	@Scripts/release-preflight.sh

.PHONY: release-publish
release-publish: release-preflight  ## Release step 2: bump, open auto-merging PR, wait for CI
	@Scripts/release-publish.sh $(PLATFORM)

.PHONY: release-tag
release-tag: release-publish  ## Release step 3: tag the merge commit + publish GitHub releases
	@Scripts/release-tag.sh $(PLATFORM)

.PHONY: release-distribute
release-distribute: release-tag  ## Release step 4: archive/export (+ upload unless UPLOAD=0)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS)

# Distribute is the likeliest step to fail (archive/export/ASC upload) and is
# safe to repeat. This standalone retry has NO prereqs — it re-distributes an
# already-tagged release after verifying the tag exists.
.PHONY: release-distribute-retry
release-distribute-retry:  ## Re-distribute an already-tagged release (no PR/tag steps)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS) --require-tag

.PHONY: release-upload
release-upload:  ## Upload the already-built dist/ package (no rebuild)
	@Scripts/release-distribute.sh $(PLATFORM) --upload-only
