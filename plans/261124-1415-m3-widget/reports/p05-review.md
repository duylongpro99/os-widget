# Báo cáo review Phase 5: Nút đã đọc và xoá, app nhận thao tác

Nhánh `widget-row-actions` đạt yêu cầu sau một sửa nhỏ, đã merge `--no-ff` vào main (`5ef2f16`). Không có phát hiện cần quyết định của người vận hành.

## Phát hiện

| # | Mức | Phát hiện | Xử lý |
|---|---|---|---|
| 1 | Nhỏ | `InboxWatcher` không có `deinit`: nếu watcher bị giải phóng mà chưa gọi `stop()`, DispatchSource không bị cancel nên file descriptor của `inbox/` không được đóng; vòng quét 60 s dùng `self?.drain()` nên tiếp tục ngủ dậy mãi khi `self` đã mất. Hiện watcher sống cùng app (giữ trong `WidgetWiring`) nên chưa xảy ra. | Sửa ở `7c4c0b6`: `isolated deinit { stop() }` (macOS 26, Swift 6.4) và vòng quét dừng khi `self` không còn. |

## Kiểm bằng cách đọc (thay cho test, theo quyết định giám sát)

- Intent: mỗi lần bấm gọi đúng một `ActionInbox.submit` (file tạm `.tmp-` rồi rename), không đụng `store.json`; log chỉ có action và id; lỗi ghi `widget.intent_failed` ở mức `error` rồi ném lại; `openAppWhenRun = false`, `isDiscoverable = false`. Extension có `AppGroupID` trong `Info.plist` và entitlement nhóm nên `StoreLocation.appGroup()` chạy được ở đó. `git grep "WidgetCenter\|store.json" apps/macos/Widget` rỗng.
- Nút: dấu tích chỉ khi `!item.isRead`, thùng rác luôn hiện, `.buttonStyle(.plain)`, nhãn trợ năng đúng.
- `InboxWatcher`: rút một lần lúc start; tạo `inbox/` trước khi mở; source được giữ trong thuộc tính, cancel handler đóng descriptor, `stop()` cancel source, task gộp và task quét. Gộp sự kiện đúng: sự kiện đầu mở một task 200 ms, các sự kiện sau bị bỏ qua khi `pendingDrain != nil`, cuối cửa sổ rút một lần. Mọi lần dùng `ItemStore` đều trên main actor (source chạy trên hàng đợi main với `MainActor.assumeIsolated`, các task kế thừa main actor), giống `QueueWatcher` và `WidgetReloader`. Không có group container thì ghi một lần `widget.inbox_disabled reason=no_container` (`started` chặn gọi lại) và không theo dõi gì.
- Không quay vòng: `drain` xoá file hỏng; nếu xoá thất bại thì thư mục không đổi nên không có sự kiện mới. Việc `drain` tự xoá file sinh đúng một sự kiện và một lần rút rỗng sau 200 ms, rồi dừng.
- Rút có thay đổi thì `items` và `queue` đổi: `WidgetReloader` thấy snapshot khác và xin reload qua chính sách gộp ≥ 5 s; `QueueWatcher` thấy id hàng đợi mới và gọi `engine.trigger()` một lần.
- Không tách phần gộp 200 ms vào `OSWidgetKit`: logic chỉ vài dòng, đọc là kiểm được, tách ra thêm một kiểu và hai file mà không giảm rủi ro thật. Để Phase 6 kiểm trên máy thật như plan.

## Kiểm trên main sau merge

- `swift test` (`apps/macos/OSWidgetKit`): 168 pass.
- `cargo test --workspace`: 187 pass (main đã có merge `vocab-ingest-book`).
- `xcodebuild … CODE_SIGNING_ALLOWED=NO build`, derivedDataPath ngoài repo: BUILD SUCCEEDED. Lần đầu thất bại vì `OSWidget.xcodeproj` ở checkout main (bị gitignore, sinh bằng `xcodegen`) chưa có `ItemIntents.swift`; chạy `xcodegen generate` trong `apps/macos` rồi build lại thì qua. Không phải lỗi mã, nhưng ai build ở checkout main cần sinh lại project.

## Câu hỏi còn mở

Không có.
