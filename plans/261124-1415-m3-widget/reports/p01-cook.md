# Phase 1 cook: widget extension target, ký và điểm nối

Session `m3-widget-p01-cook`, nhánh `widget-extension-target` (worktree `/Users/onedayin20902/personal/os-widget-wt/widget-extension-target`), tách từ main `2901e8b`. Chưa merge.

## Kết quả

Phase 1 xong theo nhánh "A đạt". App `OSWidget` nhúng extension `OSWidgetWidget.appex` (bundle id `local.oswidget.app.widget`), cùng Team ID và App Group với app, không có `network.client`. Extension có một widget khung cỡ vừa và lớn, kind `WidgetKind.items`. App có điểm nối `WidgetWiring.start(env:)` gọi `WidgetReloader(env:).start()` và `InboxWatcher(env:).start()` (hai khung rỗng cho Phase 3 và 5).

| Commit | Nội dung |
|---|---|
| `b2a7937` | `OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetKind.swift` (không import WidgetKit) |
| `9d6640a` | Target `OSWidgetWidget` và phụ thuộc nhúng trong `project.yml`; `Widget/Info.plist`, `Widget/Widget.entitlements` (XcodeGen sinh), `Widget/OSWidgetWidgetBundle.swift` |
| `a0d85ce` | `App/Widget/{WidgetWiring,WidgetReloader,InboxWatcher}.swift`; một dòng `WidgetWiring.start(env: env)` sau `SyncWiring.start(env: env)` trong `AppDelegate.swift` |
| `4a1a229` | `apps/macos/README.md`: mục Widget (target, bundle id, thêm widget bằng "Edit Widgets…") |

## Kiểm

- `swift test` trong `apps/macos/OSWidgetKit`: 127 test, 13 suite, pass. Phase 1 không nêu test mới.
- `cargo test --workspace`: 92 pass, 0 lỗi.
- `xcodegen generate` rồi `xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug -derivedDataPath <scratchpad ngoài repo> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`: BUILD SUCCEEDED, build sạch từ đầu (xoá derived data và `.xcodeproj` trước). Bundle app có `Contents/PlugIns/OSWidgetWidget.appex`.
- `plutil -p` trên `Info.plist` của `.appex`: `NSExtensionPointIdentifier => com.apple.widgetkit-extension`, `AppGroupID => 22LZWPB3XL.os-widget`, không còn `$(`.
- `git grep -n "import WidgetKit" apps/macos/OSWidgetKit`: rỗng.
- Không còn tiến trình `xcodebuild` hay `swift-build`. Không có test chập chờn.
- Kiểm cần ký (`codesign -d --entitlements -`, `pluginkit -m`) để Phase 6 như phase file ghi.

## Khác với phase file

- Kiểu widget khung đặt tên `PlaceholderWidget`, `PlaceholderProvider`, `PlaceholderEntry` thay vì một tên trùng với `ItemsWidget` mà Phase 4 tạo trong `Widget/ItemsWidget.swift`. Phase 4 chỉ cần thay `PlaceholderWidget()` bằng `ItemsWidget()` trong body và xoá ba kiểu khung, không bị lỗi khai báo trùng.
- `Widget/Info.plist` thêm `CFBundleShortVersionString` và `CFBundleVersion` như app, để phiên bản extension khớp app khi nhúng (Xcode cảnh báo khi lệch).
- Chú thích đầu `AppDelegate.swift` vẫn ghi "three parts of the app (sync, menu bar, popup)" vì phase giới hạn đúng một dòng sửa ở file này; Phase 6 (tài liệu) hoặc review có thể sửa chú thích.
- Không sửa trạng thái trong `plan.md` hay phase file (ngoài phạm vi ghi của session này); việc đó để review hoặc giám sát.
- Bước journal của cook bỏ qua vì ngoài phạm vi ghi của brief.

## Câu hỏi còn mở

Không có.
