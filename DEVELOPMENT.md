# Development

## Unit tests (pure logic)

Logic that does not need CoreGraphics private APIs or AppKit lives in
`SpaceSwitcher/SpaceSwitcher/Logic/` and is tested through the SwiftPM package at the repo root:

```
swift test
```

This needs a toolchain that includes XCTest (full Xcode, not just the Command Line Tools). If your
default developer directory is the Command Line Tools, prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Inside sandboxed environments, add
`--disable-sandbox -Xswiftc -Xfrontend -Xswiftc -disable-sandbox`.

Tests never touch real Spaces or displays.

## Build the app

The Xcode project is generated from `SpaceSwitcher/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed. After adding or removing source
files, run `xcodegen generate` in `SpaceSwitcher/` and commit the result.

```
cd SpaceSwitcher
xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher -configuration Debug \
  -derivedDataPath /tmp/ss-build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build
```

In a sandboxed shell, also pass `-IDEPackageSupportDisableManifestSandbox=1
-IDEPackageSupportDisablePluginExecutionSandbox=1 OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'`.

No release binaries are published from this repository; build from source.
