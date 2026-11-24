# Báo cáo cook Phase 5: Nút đã đọc và xoá, app nhận thao tác

Nhánh `widget-row-actions` (worktree `/Users/onedayin20902/personal/os-widget-wt/widget-row-actions`), tách từ main `934c66c`. Chưa merge.

## Kết quả

Phase 5 xong phần mã: mỗi hàng widget có nút đã đọc (chỉ khi chưa đọc) và nút xoá, intent ghi `WidgetAction` vào hộp thư, app rút hộp thư vào kho. Kiểm trên máy thật (bấm khi app chạy, khi app tắt, khi mất mạng) thuộc Phase 6.

| Bước | Commit | File |
|---|---|---|
| Hai intent và nút | `8f4e8bd` | tạo `apps/macos/Widget/ItemIntents.swift`, sửa `apps/macos/Widget/ItemRowActions.swift` |
| `InboxWatcher` | `326d275` | sửa `apps/macos/App/Widget/InboxWatcher.swift` |

- `MarkItemReadIntent` và `DeleteItemIntent`: `@Parameter var itemID`, `isDiscoverable = false`, `openAppWhenRun = false`, tiêu đề "Đánh dấu đã đọc" và "Xoá". `perform()` gọi `ActionInbox(location: try StoreLocation.appGroup()).submit(...)`, ghi `widget.intent action=<read|delete> id=<id>` ở mức `notice` (category `widget`); lỗi thì ghi `widget.intent_failed` ở mức `error` và ném lại. Không gọi `WidgetCenter`.
- `ItemRowActions`: `Button(intent:)` với `checkmark.circle` (chỉ khi `!item.isRead`) và `trash`, `.buttonStyle(.plain)`, nhãn trợ năng "Đánh dấu đã đọc" và "Xoá".
- `InboxWatcher.start()`: không có group container thì ghi một lần `widget.inbox_disabled reason=no_container` và dừng. Có thì rút ngay, tạo `inbox/` nếu thiếu, mở `DispatchSource.makeFileSystemObjectSource(.write)` trên thư mục (hàng đợi main), gộp sự kiện trong 200 ms thành một lần rút, quét dự phòng mỗi 60 s. Mỗi lần rút > 0 ghi `widget.inbox_drained count=<n>` ở mức `notice`.

## Kiểm

- `xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug -derivedDataPath <scratchpad, ngoài repo> CODE_SIGNING_ALLOWED=NO build`: BUILD SUCCEEDED, không lỗi, không cảnh báo ở ba file của phase.
- `swift test` trong `apps/macos/OSWidgetKit`: 168 pass (không thêm test, xem Sai khác).
- `cargo test --workspace`: 151 pass.
- `git grep -n "import WidgetKit" apps/macos/OSWidgetKit`: rỗng. `git grep -n "store.json" apps/macos/Widget`: rỗng.
- Không còn tiến trình `xcodebuild` hay `swift-build`. Không test flaky.

## Sai khác so với phase file

- Không có test mới. Phase file không nêu test nào ("phase này là dây nối"; logic rút đã có test ở Phase 2), và ba file của phase nằm trong target app và extension, không thuộc `swift test`. Tách phần gộp sự kiện vào `OSWidgetKit` để test được sẽ cần file ngoài bảng sở hữu, nên không làm.
- Hai intent dùng chung một hàm ghi hộp thư và log (`ItemIntentInbox`, private trong `ItemIntents.swift`) để mỗi lần bấm có đúng một dòng log; hành vi đúng như phase file.

## Ghi chú cho Phase 6

- Kiểm rủi ro `Button(intent:)`: bấm nút rồi tìm `widget.intent` trong `log show --predicate 'subsystem == "local.oswidget.app" AND category == "widget"' --info`. Có dòng đó mà không có file trong `inbox/` thì là lỗi ghi; không có cả dòng `widget.intent` lẫn `widget.intent_failed` thì intent không chạy trong extension (điều kiện "Stop and ask").
- Mỗi lần bấm sẽ kéo theo một yêu cầu reload từ app: lúc bấm app chưa biết (WidgetReloader chỉ theo dõi kho), sau khi rút thì snapshot khác snapshot gửi lần trước nên reload. Đây là hành vi đúng của chính sách reload hiện tại, nhưng tính vào ngưỡng 40 lần mỗi ngày; đếm ngày thật ở Phase 6 nên ghi số lần bấm nút.

## Câu hỏi còn mở

Không có.
