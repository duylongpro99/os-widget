# OS Widget for macOS

Menu bar agent app (`OSWidget`) and the shared Swift package `OSWidgetKit`.

- `project.yml` is the XcodeGen spec. The generated `OSWidget.xcodeproj` is not committed.
- `App/` holds the app target: entry point, environment, menu bar, popup and settings window.
  `App/Widget/` connects the app to the widget (`WidgetWiring`).
- `Widget/` holds the widget extension target `OSWidgetWidget`, embedded in the app.
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

## Widget

The app embeds a WidgetKit extension, `OSWidgetWidget.appex` (bundle id `local.oswidget.app.widget`),
in `Contents/PlugIns/`. It offers medium and large sizes and uses the same Team ID and App Group as
the app, so it reads the same store. It has no network entitlement: only the app talks to the server.
The kind string shared by both sides is `WidgetKind.items` in `OSWidgetKit`; the package itself never
imports WidgetKit.

To put the widget on the desktop, run the signed app once, then right-click the desktop, choose
"Edit Widgets…", search for "OS Widget", and drag the medium or large size onto the desktop.

## Configuration

Open the menu bar icon and choose "Cài đặt…". The Worker URL, Supabase URL and publishable key are
stored in the app's `UserDefaults`; the client token is stored in the Keychain (service
`local.oswidget.app`, account `client-token`). No token or key belongs in the repository.
