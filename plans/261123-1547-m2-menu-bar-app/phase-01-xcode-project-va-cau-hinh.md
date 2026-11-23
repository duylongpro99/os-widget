---
phase: 1
title: "Xcode project, package dùng chung và cấu hình"
status: completed
priority: P1
effort: "3h"
dependencies: []
---

# Phase 1: Xcode project, package dùng chung và cấu hình

## Goal

Có một app agent trên thanh menu build được từ `apps/macos/project.yml`, ký bằng Personal Team, có Swift package cục bộ `OSWidgetKit` với test chạy được, và có cửa sổ cài đặt lưu token client vào Keychain.

## Context

- Phụ thuộc thử nghiệm A: ký và entitlement. Trước khi bắt đầu, đọc kết quả ngày 8 trong `plans/261122-0754-m0-kiem-chung-worker-rust/reports/a-c-results.md` và chọn nhánh ở plan.md ("Nhánh theo kết quả thử nghiệm").
- Mẫu: `spikes/widget-probe/project.yml` (một chỗ đặt Team ID, `APP_GROUP_ID` suy ra từ `DEVELOPMENT_TEAM`, `LSUIElement`, entitlements sandbox và App Group), `spikes/widget-probe/App/ProbeApp.swift` (`main` tự dựng `NSApplication` với `.accessory`).
- Architecture §6: mã dùng chung (kiểu envelope, kho, view thẻ) tách thành Swift package cục bộ để widget Giai đoạn 3 và bản iPhone dùng lại.
- Vị trí trong repo: `apps/macos/`, ngang hàng `crates/`, `supabase/`. `spikes/` chỉ chứa mã bỏ đi được nên không đặt app chính thức ở đó.

## Requirements

- App tên hiển thị "OS Widget", bundle id `local.oswidget.app` (cùng tiền tố `local.oswidget` với app thử nghiệm), không có icon Dock (`LSUIElement`), chỉ một bản chạy cùng lúc.
- Entitlements: `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.application-groups = [$(TeamIdentifierPrefix)os-widget]` (bỏ dòng cuối nếu A thất bại theo nhánh App Group).
- `Info.plist` có `AppGroupID = $(APP_GROUP_ID)` như app thử nghiệm, để Swift đọc định danh group mà không viết cứng Team ID.
- `OSWidgetKit` là package Swift 6, platform macOS 26, một target thư viện và một target test dùng Swift Testing. Chạy được bằng `swift test` mà không cần ký.
- Cấu hình (`OSWidgetKit/Sources/OSWidgetKit/Config/`):
  - `AppConfig`: URL Worker, URL Supabase, khoá publishable, đọc ghi `UserDefaults` chuẩn của app.
  - `KeychainTokenStore`: đọc, ghi, xoá token client trong Keychain (generic password, service `local.oswidget.app`, account `client-token`).
  - `StoreLocation`: trả URL thư mục chứa kho cục bộ. Nhánh A đạt: `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` với `AppGroupID`. Nhánh App Group thất bại: Application Support của app. Đây là chỗ duy nhất biết vị trí kho.
- Cửa sổ cài đặt (SwiftUI trong `NSWindow`, mở từ menu, được phép kích hoạt app vì người dùng chủ động mở): bốn ô (URL Worker, token client, URL Supabase, khoá publishable), nút lưu. Token hiển thị dạng ẩn.
- Điểm nối cho các phase sau, viết sẵn chữ ký trong file khung (thân hàm rỗng hoặc `TODO` có kiểm của compiler):
  - `AppEnvironment`: giữ `AppConfig`, `KeychainTokenStore` và `ItemStore`. Phase 1 tạo `ItemStore` dạng khung rỗng (`@MainActor @Observable final class` với `static func live() -> ItemStore`) để `AppEnvironment` không phải sửa lại; Phase 2 viết thân.
  - `SyncWiring.start(env:)` (Phase 3 sở hữu).
  - `MenuBarController(env:)` với `anchorRect() -> NSRect?` và `isListOpen: Bool` (Phase 4 sở hữu).
  - `PopupController(env:, anchor: () -> NSRect?, isListOpen: () -> Bool)` (Phase 5 sở hữu).
- `AppDelegate` dựng `AppEnvironment` rồi gọi ba điểm nối trên, không chứa logic khác.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`, trừ khi ghi khác.

- Create: `project.yml`, `README.md` (cách sinh project và build, ngắn)
- Create: `App/Info.plist`, `App/App.entitlements`, `App/AppDelegate.swift`, `App/AppEnvironment.swift`, `App/SyncWiring.swift`, `App/MenuBar/MenuBarController.swift`, `App/Popup/PopupController.swift`, `App/Settings/SettingsWindow.swift`
- Create: `OSWidgetKit/Package.swift`, `OSWidgetKit/Sources/OSWidgetKit/Config/AppConfig.swift`, `OSWidgetKit/Sources/OSWidgetKit/Config/KeychainTokenStore.swift`, `OSWidgetKit/Sources/OSWidgetKit/Config/StoreLocation.swift`, `OSWidgetKit/Sources/OSWidgetKit/Store/ItemStore.swift` (khung rỗng, giao cho Phase 2), `OSWidgetKit/Tests/OSWidgetKitTests/ConfigTests.swift`
- Modify (gốc repo): `.gitignore` thêm `apps/macos/*.xcodeproj/`

## Tasks & Steps

- [ ] Ghi nhánh A đã chọn vào đầu phần ghi chú của phase này (một dòng, kèm ngày đọc kết quả).
- [ ] `project.yml`: một target `OSWidget` (application, macOS), phụ thuộc package cục bộ `OSWidgetKit`; `DEVELOPMENT_TEAM: 22LZWPB3XL`, `APP_GROUP_ID: $(DEVELOPMENT_TEAM).os-widget`, `CODE_SIGN_STYLE: Automatic`, `SWIFT_VERSION: "6.0"`, `ENABLE_HARDENED_RUNTIME: YES`, deployment target 26.0. Không thêm target widget.
- [ ] Entitlements và `Info.plist` theo Requirements.
- [ ] `AppDelegate` theo mẫu `ProbeApp.main` (`setActivationPolicy(.accessory)`); thoát nếu đã có bản khác cùng bundle id đang chạy.
- [ ] Package `OSWidgetKit` và ba file `Config/`.
- [ ] Cửa sổ cài đặt; tạm thời mở từ một mục menu tối thiểu trong `MenuBarController` khung (Phase 4 thay bằng menu đầy đủ).
- [ ] Test `ConfigTests`: `AppConfig` đọc ghi qua một `UserDefaults(suiteName:)` tạm; `StoreLocation` trả thư mục tồn tại và ghi được khi chạy trong test (dùng thư mục tạm qua tham số, không đụng group container thật). Keychain chỉ test bằng tay vì `swift test` không có entitlement Keychain của app.
- [ ] `xcodegen generate` trong `apps/macos/`, build Debug với `-allowProvisioningUpdates`.

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass.
- `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug -allowProvisioningUpdates build` thành công.
- `codesign -d --entitlements - <app>` liệt kê sandbox, network client và App Group `22LZWPB3XL.os-widget` (hoặc không có App Group theo nhánh).
- Chạy app: có icon trên thanh menu, không có icon Dock; mở cài đặt, lưu token, thoát và mở lại thì token vẫn còn; `security find-generic-password -s local.oswidget.app -a client-token` thấy mục (không in mật khẩu).
- `git status` không có `.xcodeproj`.

## Risk Assessment

- Sandbox chặn Keychain hoặc mạng: entitlement `network.client` là bắt buộc; Keychain generic password trong container của app không cần entitlement thêm. Nếu lỗi, ghi nguyên văn và dừng.
- Package cục bộ trong XcodeGen: khai báo trong `packages:` với `path: OSWidgetKit` và `dependencies: - package: OSWidgetKit`. Sai cấu hình thì sửa `project.yml`, không tạo project bằng tay.
- App M2 và WidgetProbe cùng group container: app M2 chỉ ghi `store.json` (Phase 2), không đọc ghi `UserDefaults(suiteName:)` của group.

## Rollback

Xoá `apps/macos/` và dòng `.gitignore` vừa thêm. Không có gì ngoài repo bị đổi, trừ mục Keychain `local.oswidget.app` (xoá bằng `security delete-generic-password -s local.oswidget.app -a client-token`) và bản app Debug trong DerivedData.

## Ghi chú

- Nhánh A chưa chọn: kết quả kiểm ngày 8 của thử nghiệm A chưa có (2026-11-30). Mã viết theo nhánh "A đạt" (entitlement App Group, `StoreLocation.appGroup` dùng group container qua `AppGroupID`).
- Quyết định của operator (2026-11-23, khoảng 21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Phase này chỉ kiểm bằng `swift test` và build Debug không ký.
- Các mục Verification sau hoãn tới sau 30/11, làm ở Phase 6: build có ký (`-allowProvisioningUpdates`); `codesign -d --entitlements -` xác nhận sandbox, network client và App Group; icon trên thanh menu, không có icon Dock; vòng lưu và đọc lại token qua Keychain; `StoreLocation.appGroup` với group container thật.
- Báo cáo: [cook](../reports/cook-261123-m2-p01.md), [review](../reports/review-261123-m2-p01.md).
