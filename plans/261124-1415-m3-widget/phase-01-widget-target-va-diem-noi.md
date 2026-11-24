---
phase: 1
title: "Widget extension target, ký và điểm nối"
status: pending
priority: P1
effort: "3h"
dependencies: []
---

# Phase 1: Widget extension target, ký và điểm nối

## Goal

`apps/macos/project.yml` sinh thêm một widget extension nhúng trong app `OSWidget`, cùng Team ID và App Group với app; extension build được với một widget khung; app có một điểm nối duy nhất `WidgetWiring.start(env:)` để Phase 3 và 5 cắm vào mà không sửa chung file.

## Context

- Phụ thuộc thử nghiệm A: ký và entitlement. Theo nhánh "A đạt" (plan.md): ký Personal Team `22LZWPB3XL`, App Group `$(TeamIdentifierPrefix)os-widget` như app và như `spikes/widget-probe/project.yml` (target `ProbeWidget`). Nếu A trượt vì chữ ký: không đổi gì ở phase này, Phase 6 cài bằng script build lại. Nếu A trượt vì App Group: bỏ `application-groups` ở cả hai target, thêm `network.server` cho app và `network.client` cho extension (plan bổ sung sau 2026-11-30).
- Mẫu: `spikes/widget-probe/project.yml` (app `dependencies: - target: ProbeWidget, embed: true, codeSign: true`; extension `type: app-extension`, `NSExtensionPointIdentifier: com.apple.widgetkit-extension`, Info.plist có `AppGroupID`). Chỉ đọc, không sửa spike.
- `StoreLocation.appGroup(bundle:)` đọc khoá `AppGroupID` trong `Info.plist` của bundle đang chạy, nên extension cần đúng khoá đó để đọc cùng group container.
- `App/AppDelegate.swift` hiện gọi `SyncWiring.start(env:)` rồi dựng `MenuBarController` và `PopupController`.

## Requirements

- Target mới `OSWidgetWidget`, `type: app-extension`, `platform: macOS`, `sources: [Widget]`, phụ thuộc package `OSWidgetKit`, bundle id `local.oswidget.app.widget` (phải có tiền tố bundle id của app `local.oswidget.app`).
- Entitlement của extension: `com.apple.security.app-sandbox: true`, `com.apple.security.application-groups: [$(TeamIdentifierPrefix)os-widget]`. Không có `network.client`.
- `Widget/Info.plist`: `AppGroupID: $(APP_GROUP_ID)`, `NSExtension.NSExtensionPointIdentifier: com.apple.widgetkit-extension`, `CFBundleDisplayName: OS Widget`.
- Target app thêm `dependencies: - target: OSWidgetWidget, embed: true, codeSign: true`.
- `OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetKind.swift`: `public enum WidgetKind { public static let items = "OSWidgetItems" }`. App và extension cùng dùng chuỗi này (app khi gọi `reloadTimelines(ofKind:)`, extension khi khai `StaticConfiguration(kind:)`). File không import WidgetKit.
- `Widget/OSWidgetWidgetBundle.swift`: `@main struct OSWidgetWidgetBundle: WidgetBundle` chứa một widget khung (kind `WidgetKind.items`, `supportedFamilies([.systemMedium, .systemLarge])`, view ghi "OS Widget"), để target build và chạy được. Phase 4 thay nội dung.
- `App/Widget/WidgetWiring.swift`: `@MainActor enum WidgetWiring { static func start(env: AppEnvironment) }` giữ hai đối tượng sống suốt đời app: `WidgetReloader(env:)` và `InboxWatcher(env:)`, gọi `start()` của từng cái. Gọi lần hai không làm gì.
- Khung rỗng với chữ ký cố định: `App/Widget/WidgetReloader.swift` (`@MainActor final class WidgetReloader { init(env: AppEnvironment); func start() }`), `App/Widget/InboxWatcher.swift` (cùng dạng). Thân do Phase 3 và Phase 5 viết.
- `App/AppDelegate.swift`: thêm đúng một dòng `WidgetWiring.start(env: env)` ngay sau `SyncWiring.start(env: env)`.
- `apps/macos/README.md`: thêm mục widget (target, bundle id, cách thêm widget lên desktop bằng "Edit Widgets").

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`.

- Modify: `project.yml`, `App/AppDelegate.swift`, `README.md`
- Create: `Widget/Info.plist`, `Widget/Widget.entitlements` (XcodeGen sinh từ `properties`, như app), `Widget/OSWidgetWidgetBundle.swift`, `App/Widget/WidgetWiring.swift`, `App/Widget/WidgetReloader.swift`, `App/Widget/InboxWatcher.swift`, `OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetKind.swift`

## Tasks & Steps

- [ ] Thêm target `OSWidgetWidget` và phụ thuộc nhúng vào `project.yml` theo mẫu spike, giữ `DEVELOPMENT_TEAM` chỉ ở một chỗ.
- [ ] Tạo `Widget/Info.plist`, entitlement, bundle khung.
- [ ] Tạo `WidgetKind.swift`, `WidgetWiring.swift` và hai khung rỗng; thêm một dòng vào `AppDelegate.swift`.
- [ ] `xcodegen generate` rồi build Debug không ký.
- [ ] Cập nhật `README.md`.

## Verification

- `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug -derivedDataPath <ngoài repo> CODE_SIGNING_ALLOWED=NO build` thành công; bundle app có `Contents/PlugIns/OSWidgetWidget.appex`.
- `plutil -p` trên `Info.plist` của `.appex` có `NSExtensionPointIdentifier = com.apple.widgetkit-extension` và `AppGroupID` đã thay biến (không còn `$(`).
- `cd apps/macos/OSWidgetKit && swift test` vẫn pass; `git grep -n "import WidgetKit" apps/macos/OSWidgetKit` rỗng.
- Kiểm cần ký (entitlement thật của app và extension bằng `codesign -d --entitlements -`, `pluginkit -m -i local.oswidget.app.widget`) chuyển sang Phase 6, như M2 (quyết định "Cook ngay, chưa ký/cài").

## Risk Assessment

- Bundle id extension sai tiền tố thì Xcode từ chối nhúng: dùng đúng `local.oswidget.app.widget`.
- Ký tự động với Personal Team có thể đòi tạo App ID mới cho extension ở lần build ký đầu tiên (Phase 6, `-allowProvisioningUpdates`). Spike đã ký extension cùng cách nên rủi ro thấp; nếu Xcode đòi chứng chỉ mới thì dừng và báo (không tạo hay thu hồi chứng chỉ).
- Package tĩnh `OSWidgetKit` được liên kết vào hai binary; không có trạng thái toàn cục dùng chung giữa tiến trình nên không sao.

## Rollback

Bỏ target `OSWidgetWidget` và phụ thuộc nhúng khỏi `project.yml`, xoá `Widget/`, `App/Widget/`, `WidgetKind.swift`, bỏ dòng `WidgetWiring.start` khỏi `AppDelegate.swift`. App M2 build lại như cũ.
