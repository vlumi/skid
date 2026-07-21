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

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Skid.xcodeproj .build-xcode Packages/SkidCore/.build
	@echo "removed Skid.xcodeproj, .build-xcode, package .build"
