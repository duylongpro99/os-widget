---
phase: 2
title: "Đọc kho, snapshot và hộp thư thao tác"
status: completed
priority: P1
effort: "5h"
dependencies: []
---

# Phase 2: Đọc kho, snapshot và hộp thư thao tác

## Goal

`OSWidgetKit` có (1) cách đọc `store.json` chỉ-đọc từ một tiến trình khác, (2) kiểu `WidgetSnapshot` mô tả đúng những gì widget hiện, (3) hộp thư thao tác `ActionInbox` để widget ghi đã đọc và xoá mà không ghi `store.json`, và (4) `ItemStore.drain(_:)` để app rút hộp thư vào kho và hàng đợi M2. Test chứng minh ghi đồng thời không mất hay nhân đôi thao tác.

## Context

- Thiết kế ghi giữa hai tiến trình: plan.md, mục "Thiết kế ghi giữa hai tiến trình". App là tiến trình duy nhất ghi `store.json`.
- Phụ thuộc thử nghiệm A: hộp thư nằm cạnh `store.json` trong thư mục của `StoreLocation` (group container ở nhánh A đạt). Ở nhánh A trượt vì App Group, `WidgetSnapshot` và `WidgetAction` giữ nguyên, chỉ đường vận chuyển đổi; vì vậy hai kiểu này không chứa mã đọc ghi file.
- `ItemStore` (`Store/ItemStore.swift`) có `struct StoreFile` private với giải mã chịu lỗi (`LossyArray`), ghi nguyên tử bằng `data.write(to:options: .atomic)`, đọc bằng `ServerJSON.makeDecoder()`. `markRead(_:)` và `delete(_:)` đã áp quy tắc: mục đã xoá không nhận thao tác nào, xoá thắng đã đọc, gộp theo `itemId`.
- `Item.isVisible(at:)` và thứ tự "mới nhất trước" (`createdAt` giảm dần, rồi `id` giảm dần) có sẵn.

## Requirements

**Đọc kho chỉ-đọc** (`Store/StoreFile.swift`, `Store/StoreReader.swift`):

- Chuyển `StoreFile` ra file riêng (internal), `ItemStore` dùng lại; định dạng file không đổi (`version` 1), nên app M2 đang cài và bản mới đọc cùng file.
- `public enum StoreReader { public static func read(location: StoreLocation) -> StoreContents? }` trả `items`, `cursor` hoặc `nil` khi không có file hay file hỏng (ghi log `store.reader_failed`). Không bao giờ ghi, tạo thư mục hay xoá gì. Không `@MainActor`.

**Snapshot** (`Widget/WidgetSnapshot.swift`):

- `public struct WidgetSnapshot: Codable, Sendable, Hashable`: `items: [Item]` (tối đa `limit`, mặc định `WidgetSnapshot.maxItems = 6`, mục hiển thị mới nhất trước), `unreadCount: Int` (mọi mục hiển thị chưa đọc, không chỉ 6 mục đầu), `nextExpiry: Date?` (hạn gần nhất trong các mục hiển thị, để timeline tự bỏ mục hết hạn).
- `public static func make(items: [Item], pending: [WidgetAction], now: Date, limit: Int = maxItems) -> WidgetSnapshot`, hàm thuần: phủ `pending` lên `items` (chờ xoá thì ẩn, chờ đọc thì `readAt = createdAt` của thao tác), bỏ mục không hiển thị, sắp xếp, cắt. Không chứa thời điểm hiện tại hay gì thay đổi theo thời gian ngoài dữ liệu, để Phase 3 so sánh bằng `==`.
- Số mục mỗi cỡ (3 và 6) theo câu hỏi 2; mục đã đọc vẫn có trong snapshot theo câu hỏi 3. Nếu operator trả lời khác, đổi `maxItems` hoặc bộ lọc ở đây.

**Hộp thư** (`Widget/WidgetAction.swift`, `Widget/ActionInbox.swift`):

- `public struct WidgetAction: Codable, Sendable, Hashable, Identifiable`: `id: UUID`, `itemId: String` (giữ nguyên dạng server trả, không chuẩn hoá), `operation: Operation` (`.markRead`, `.delete`), `createdAt: Date`.
- `public struct ActionInbox: Sendable { init(location: StoreLocation) }`, thư mục `inbox/` cạnh `store.json`:
  - `submit(_ action:) throws`: tạo thư mục nếu thiếu, ghi `.tmp-<uuid>.json` rồi `rename` thành `<uuid>.json`.
  - `pending() -> [WidgetAction]`: đọc mọi `*.json` không có tiền tố `.tmp-`, sắp theo `createdAt`; file không giải mã được bị bỏ qua và trả trong danh sách `corrupt` để `drain` xoá.
  - `remove(_ ids:)`: xoá file theo id; file đã mất thì bỏ qua.
- `ItemStore.drain(_ inbox: ActionInbox) -> Int` (`@MainActor`, trong `ItemStore.swift`): với mỗi thao tác theo thứ tự, gọi `markRead` hoặc `delete` (mục không có trong kho hoặc đã xoá thì bỏ qua), sau đó mới `remove` các file đã xử lý và file hỏng. Trả số thao tác đã áp. Áp lại một file chưa kịp xoá (app chết giữa chừng) không đổi kết quả.
- Log category `widget` (thêm `Log.widget` cạnh `Log.store`): `widget.inbox_corrupt name=…`, không ghi nội dung.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/OSWidgetKit/`.

- Modify: `Sources/OSWidgetKit/Store/ItemStore.swift` (dùng `StoreFile` tách ra, thêm `drain`), `Sources/OSWidgetKit/Model/Item.swift` (chỉ thêm `Log.widget` vào `enum Log`)
- Create: `Sources/OSWidgetKit/Store/StoreFile.swift`, `Sources/OSWidgetKit/Store/StoreReader.swift`, `Sources/OSWidgetKit/Widget/WidgetSnapshot.swift`, `Sources/OSWidgetKit/Widget/WidgetAction.swift`, `Sources/OSWidgetKit/Widget/ActionInbox.swift`
- Create: `Tests/OSWidgetKitTests/StoreReaderTests.swift`, `Tests/OSWidgetKitTests/WidgetSnapshotTests.swift`, `Tests/OSWidgetKitTests/ActionInboxTests.swift`

## Tasks & Steps

- [ ] Tách `StoreFile`; chạy lại toàn bộ test cũ để chắc định dạng không đổi.
- [ ] `StoreReader`, `WidgetSnapshot.make`, `WidgetAction`, `ActionInbox`, `ItemStore.drain`.
- [ ] Test (bảng dưới).

| Test | Kiểm |
|---|---|
| Đọc chỉ-đọc | File do `ItemStore` ghi được `StoreReader` đọc ra cùng `items`; thời điểm sửa đổi và nội dung file không đổi sau khi đọc; không có file hoặc file hỏng trả `nil` |
| Tương thích | Một `store.json` dạng M2 (fixture viết tay đúng các khoá hiện có) vẫn nạp được bằng `ItemStore` và `StoreReader` |
| Snapshot | Mới nhất trước; cắt ở `limit`; mục đã đọc vẫn có; mục đã xoá và hết hạn bị bỏ; `unreadCount` đếm cả mục ngoài 6 mục đầu; `nextExpiry` là hạn gần nhất |
| Phủ thao tác | Chờ xoá ẩn mục và giảm `unreadCount`; chờ đọc hiện đã đọc; thao tác cho mục không có thì bỏ qua |
| So sánh | Hai snapshot dựng từ cùng dữ liệu ở hai thời điểm khác nhau bằng nhau; đổi trạng thái đọc của một mục trong 6 mục đầu làm snapshot khác; đổi mục thứ 7 thì không |
| Hộp thư | `submit` rồi `pending` trả đúng thao tác; file `.tmp-` bị bỏ qua; file hỏng không làm hỏng các file khác và bị `drain` xoá |
| Rút | `drain` gọi đúng quy tắc M2 (đọc rồi xoá cùng mục để lại một thao tác xoá trong `queue`), làm trống hộp thư, ghi `store.json`; mục không có trong kho bị bỏ và file bị xoá |
| Chết giữa chừng | Áp các thao tác, không xoá file, rút lại: `items` và `queue` giống hệt một lần rút |
| Đồng thời | 8 luồng, mỗi luồng `submit` 25 thao tác cho 25 mục khác nhau, trong khi một task `@MainActor` rút liên tục; cuối cùng rút thêm một lần: đủ 200 thao tác đã áp về kết quả, hộp thư rỗng, không lỗi giải mã, `store.json` chỉ do `ItemStore` ghi |

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass (test cũ và mới).
- `git grep -n "import WidgetKit" apps/macos/OSWidgetKit` rỗng.
- `git grep -n "store.json\|StoreFile" apps/macos/OSWidgetKit/Sources` chỉ thấy trong `Store/`.

## Risk Assessment

- Sandbox của extension: ghi vào group container cần entitlement App Group (Phase 1). Test ở đây dùng thư mục tạm; ghi thật từ extension kiểm ở Phase 6.
- `rename` nguyên tử chỉ khi cùng ổ đĩa: file tạm đặt ngay trong `inbox/`.
- Đọc `store.json` đúng lúc app đổi tên file mới vào: `.atomic` của Foundation thay file bằng rename nên người đọc thấy bản cũ hoặc bản mới, không thấy bản dở.
- Đổi định dạng `store.json` làm app M2 đang cài đọc sai: không đổi khoá hay `version` nào; test tương thích canh việc này.

## Rollback

Hoàn lại `ItemStore.swift` và `Item.swift`, xoá các file mới. Thư mục `inbox/` trong group container (nếu đã có) xoá được an toàn: thao tác chưa rút sẽ mất, mục vẫn đúng theo server ở lần sync sau.
