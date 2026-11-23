# OS Widget for macOS

Menu bar agent app (`OSWidget`) and the shared Swift package `OSWidgetKit`.

- `project.yml` is the XcodeGen spec. The generated `OSWidget.xcodeproj` is not committed.
- `App/` holds the app target: entry point, environment, menu bar, popup and settings window.
- `OSWidgetKit/` holds code meant to be shared with a future widget and iPhone app (configuration,
  local store).

The Team ID is set once, as `DEVELOPMENT_TEAM` in `project.yml`. The App Group
(`<TeamID>.os-widget`) and `AppGroupID` in `Info.plist` derive from it, so changing teams is a
one-line edit.

## Test the package

```sh
cd apps/macos/OSWidgetKit
swift test
```

## Generate and build the app

```sh
cd apps/macos
xcodegen generate

# Signed build with the Personal Team (needed to run the app with its entitlements)
xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug -allowProvisioningUpdates build

# Compile-only check, no signing
xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug \
  -derivedDataPath /tmp/oswidget-dd CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build
```

## Configuration

Open the menu bar icon and choose "Cài đặt…". The Worker URL, Supabase URL and publishable key are
stored in the app's `UserDefaults`; the client token is stored in the Keychain (service
`local.oswidget.app`, account `client-token`). No token or key belongs in the repository.
