# Phase 1 review: widget extension target, ký và điểm nối

Session `m3-widget-p01-review`, review nhánh `widget-extension-target` (head cook `c2200bd`), đã merge vào main bằng `--no-ff`.

## Kết quả

Phase 1 đạt. Không có phát hiện nào cần operator quyết. Một sửa nhỏ trên nhánh theo quyết định của giám sát:

| Phát hiện | Sửa |
|---|---|
| Chú thích đầu `AppDelegate.swift` vẫn ghi "three parts of the app (sync, menu bar, popup)" sau khi thêm `WidgetWiring` | `76bfbc8` docs(macos): list widget wiring among the app parts (chỉ sửa chú thích) |

Merge: `06eaf26`. Trạng thái phase 1 "Completed" trong `plan.md` và phase file ở commit riêng trên main.

## Đã kiểm

- `project.yml`: target `OSWidgetWidget` `type: app-extension`, `platform: macOS`, `sources: [Widget]`, phụ thuộc `OSWidgetKit`; bundle id `local.oswidget.app.widget` (đúng tiền tố app); app phụ thuộc `target: OSWidgetWidget, embed: true, codeSign: true` như spike. `DEVELOPMENT_TEAM` chỉ đặt một lần ở `settings.base`; App Group của extension `$(TeamIdentifierPrefix)os-widget` và `AppGroupID: $(APP_GROUP_ID)` suy ra từ đó như app.
- Entitlement extension: `app-sandbox: true`, `application-groups`, không có `network.client`. Hardened runtime kế thừa từ cài đặt chung như spike.
- `Widget/Info.plist` khớp `spikes/widget-probe/Widget/Info.plist` (`XPC!`, `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, `AppGroupID`); khác duy nhất là phiên bản lấy từ `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` (đã được chấp nhận). `StoreLocation` đọc đúng khoá `AppGroupID`.
- Chữ ký điểm nối đúng plan: `@MainActor enum WidgetWiring { static func start(env:) }` (gọi lần hai không làm gì), `WidgetReloader(env:)`/`InboxWatcher(env:)` là `@MainActor final class` với `start()`. Phase 3 và 5 chỉ cần viết thân hai lớp này.
- `AppDelegate.swift`: đúng một dòng logic `WidgetWiring.start(env: env)` sau `SyncWiring.start(env: env)`, cộng sửa chú thích ở trên.
- `WidgetKind.swift` không import WidgetKit; `git grep "import WidgetKit" apps/macos/OSWidgetKit` rỗng.
- Build lại từ đầu trong scratchpad (xoá `.xcodeproj`, derived data mới): `xcodegen generate` + `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` BUILD SUCCEEDED, không cảnh báo trình biên dịch (chỉ dòng thông tin của `appintentsmetadataprocessor` vì chưa dùng AppIntents). `Contents/PlugIns/OSWidgetWidget.appex` có mặt; `Info.plist` của appex: `AppGroupID => 22LZWPB3XL.os-widget`, `CFBundleIdentifier => local.oswidget.app.widget`, phiên bản khớp app (0.1/1), không còn `$(`.
- Nhánh: `swift test` 127 test, 13 suite pass; `cargo test --workspace` 92 pass.
- Sau merge trên main: xem mục dưới.

## Chưa kiểm (để Phase 6)

Entitlement thật sau khi ký (`codesign -d --entitlements -`) và `pluginkit -m -i local.oswidget.app.widget`: cần build có ký và cài, ngoài phạm vi session này.

## Câu hỏi còn mở

Không có.
