---
phase: 5
title: "Nút đã đọc và xoá, app nhận thao tác"
status: pending
priority: P1
effort: "3h"
dependencies: [1, 2, 4]
---

# Phase 5: Nút đã đọc và xoá, app nhận thao tác

## Goal

Mỗi hàng trong widget có nút đã đọc và xoá. Bấm nút ghi một `WidgetAction` vào hộp thư, widget vẽ lại ngay với thao tác đã phủ lên; app rút hộp thư vào kho trong vòng một giây khi đang chạy (hoặc lúc khởi động khi đang tắt), và hàng đợi M2 gửi lên server.

## Context

- Thiết kế: plan.md, mục "Thiết kế ghi giữa hai tiến trình". Phase 2 cung cấp `WidgetAction`, `ActionInbox`, `ItemStore.drain(_:)`; Phase 4 cung cấp `ItemRow` và khung `ItemRowActions`; Phase 1 cung cấp khung `App/Widget/InboxWatcher.swift` (`init(env:)`, `start()`).
- Phụ thuộc thử nghiệm A: intent ghi file vào group container. Ở nhánh A trượt vì App Group, `perform()` đổi sang `POST /actions` tới listener localhost của app, và `InboxWatcher` thành listener đó; nút và `ItemStore.drain` theo cùng thao tác giữ nguyên.
- `QueueWatcher` (`Sync/Triggers.swift`) đã kích hoạt vòng sync khi hàng đợi có thao tác mới, nên rút hộp thư vào kho là đủ để thao tác được gửi.
- Câu hỏi 4: hai biểu tượng luôn hiện, dấu tích chỉ khi chưa đọc.

## Requirements

**Intent** (`Widget/ItemIntents.swift`):

- `struct MarkItemReadIntent: AppIntent` và `struct DeleteItemIntent: AppIntent`, mỗi cái có `@Parameter var itemID: String`, `static let isDiscoverable = false`, `static let openAppWhenRun = false`, tiêu đề tiếng Việt ("Đánh dấu đã đọc", "Xoá").
- `perform()`: `ActionInbox(location: try StoreLocation.appGroup()).submit(WidgetAction(itemId:operation:createdAt:))`, ghi `widget.intent action=<read|delete> id=<itemId>` ở mức `notice`, category `widget`; lỗi thì ghi `widget.intent_failed` và ném lỗi (không nuốt). WidgetKit tự chạy lại timeline sau khi intent xong; không gọi `WidgetCenter` trong extension.

**Nút** (`Widget/ItemRowActions.swift`):

- `Button(intent: MarkItemReadIntent(itemID: item.id))` với `Image(systemName: "checkmark.circle")`, chỉ khi mục chưa đọc; `Button(intent: DeleteItemIntent(itemID: item.id))` với `Image(systemName: "trash")`. `.buttonStyle(.plain)`, nhãn trợ năng "Đánh dấu đã đọc" và "Xoá".

**App nhận thao tác** (`App/Widget/InboxWatcher.swift`):

- `start()`: rút một lần ngay (thao tác bấm khi app tắt), mở `DispatchSource.makeFileSystemObjectSource` trên thư mục `inbox/` với sự kiện `.write` (tạo thư mục trước nếu thiếu), và hẹn giờ quét dự phòng mỗi 60 s. Mỗi lần: `env.store.drain(inbox)` trên main actor; trả về > 0 thì ghi `widget.inbox_drained count=<n>` ở mức `notice`.
- Gộp sự kiện: nhiều sự kiện thư mục trong vòng 200 ms chỉ rút một lần.
- Kho chạy trong bộ nhớ (không có group container) thì không theo dõi gì, ghi một lần `widget.inbox_disabled reason=no_container`.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`.

- Modify: `Widget/ItemRowActions.swift`, `App/Widget/InboxWatcher.swift`
- Create: `Widget/ItemIntents.swift`

## Tasks & Steps

- [ ] Hai intent và nút.
- [ ] `InboxWatcher`: rút lúc khởi động, DispatchSource, quét dự phòng, gộp sự kiện, log.
- [ ] Build Debug không ký; chạy lại `swift test`.

## Verification

- `xcodebuild … CODE_SIGNING_ALLOWED=NO build` thành công; `swift test` pass.
- Logic rút và quy tắc thao tác đã có test ở Phase 2; phase này là dây nối, kiểm trên máy thật ở Phase 6 (bấm nút khi app chạy, khi app tắt, khi mất mạng).
- `git grep -n "store.json" apps/macos/Widget` rỗng (extension không đụng tới file kho ngoài `StoreReader`).

## Risk Assessment

- Nút `Button(intent:)` của widget macOS chạy intent trong extension; nếu không có file nào xuất hiện ở `inbox/` khi bấm ở Phase 6, đây là điều kiện "Stop and ask" của plan.
- DispatchSource trên thư mục chỉ báo khi danh sách file trong thư mục đổi; `rename` file tạm thành file thật là một lần đổi như vậy. Quét 60 s phủ trường hợp lỡ sự kiện.
- Bấm nút hai lần nhanh tạo hai file cùng mục: `drain` áp quy tắc gộp M2 nên chỉ một thao tác gửi đi.

## Rollback

Trả `ItemRowActions.swift` và `InboxWatcher.swift` về khung rỗng, xoá `ItemIntents.swift`. Thao tác còn trong `inbox/` không được rút; xoá thư mục đó là an toàn.
