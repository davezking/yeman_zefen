# Shortcuts for the release steps. The details are in docs/release-ios.md and docs/release-android.md.

.PHONY: ios-release ios-symbols

# Build the prod IPA for TestFlight (on a Mac with Xcode).
ios-release:
	app/tool/ios_release.sh build

# Upload the dSYMs and Dart symbols of the last ios-release to Crashlytics.
ios-symbols:
	app/tool/ios_release.sh symbols
