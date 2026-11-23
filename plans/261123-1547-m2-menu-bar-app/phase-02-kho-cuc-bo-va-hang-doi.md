---
phase: 2
title: "Mô hình, kho cục bộ và hàng đợi thao tác"
status: pending
priority: P1
effort: "4h"
dependencies: [1]
---

# Phase 2: Mô hình, kho cục bộ và hàng đợi thao tác

## Goal

`OSWidgetKit` có kiểu dữ liệu cho mục và sự kiện giải mã được mọi `kind`, một kho cục bộ lưu bền (mục, cursor, hàng đợi thao tác, cài đặt popup) với các phép áp dụng idempotent, và test chứng minh các quy tắc đồng bộ của architecture §5.

## Context

- Phụ thuộc thử nghiệm A: chỉ vị trí kho, đã gói trong `StoreLocation` ở Phase 1. Không thay đổi gì khác theo nhánh A.
- Ràng buộc từ B: kho không biết gì về WidgetKit; Giai đoạn 3 (widget hoặc cửa sổ desktop) đọc cùng định dạng file này.
- Hình dạng dữ liệu theo architecture §4.1 và §4.3: `GET /items` trả `{"seq", "items"}`, mỗi mục là một dòng bảng `items` (`id`, `kind`, `source`, `priority`, `title`, `summary`, `url`, `body`, `dedupe_key`, `created_at`, `expires_at`, `read_at`, `deleted_at`); `GET /events` trả mảng `{seq, type, item_id, item?}`, `item` có ở `item.created` và có thể là `null` khi mục đã bị dọn hẳn.
- Quy tắc tiến hoá (architecture §3.3): `kind` lạ hiển thị `title` và `summary`; block lạ bị bỏ qua.

## Requirements

**Mô hình** (`Model/`):

- `Item`: các trường của dòng `items`; `kind` là `String`; `content` là enum `ItemContent` gồm `.notification(text: String?)`, `.generic(blocks: [Block])`, `.unknown`. `vocab` ở M2 giải mã thành `.unknown` (view `vocab` là Giai đoạn 4). Giải mã `body` lỗi thì rơi về `.unknown`, không làm hỏng cả mục; thiếu `title` hoặc `summary` mới là lỗi của mục đó (bỏ mục, ghi log).
- `Block`: `heading`, `text`, `fields`, `list`, `image`, `code`, `link` theo bảng ở architecture §3.2; `type` lạ thành `.unsupported` và view bỏ qua.
- `ServerEvent`: `seq: Int64`, `type` (`item.created`, `item.read`, `item.unread`, `item.deleted`, loại khác bị bỏ qua), `itemId`, `item: Item?`.
- Ngày giờ giải mã ISO 8601 có phần lẻ giây (dạng PostgREST trả về).

**Kho** (`Store/`):

- Một file `store.json` trong thư mục của `StoreLocation`, ghi nguyên tử (ghi file tạm rồi thay), gồm: `cursor: Int64?`, `items: [Item]`, `queue: [PendingAction]`, `popupSettings`, `lastFullSyncAt`. Dữ liệu nhỏ (mục sống 7 ngày, vài trăm mục), nên một file JSON là đủ.
- Kho là `@MainActor @Observable`; UI ở Phase 4 và 5 quan sát trực tiếp.
- Mục hiển thị: chưa xoá, `expires_at` rỗng hoặc ở tương lai, sắp xếp `created_at` giảm dần. `unreadCount` đếm trên mục hiển thị. Mục hết hạn bị bỏ khỏi file ở lần ghi kế tiếp (FR-23).
- Phép áp dụng, tất cả idempotent:
  - `apply(events:)`: `item.created` có `item` thì thêm hoặc thay mục cùng `id`, `item: null` thì bỏ qua; `item.read` đặt đã đọc; `item.unread` bỏ đọc; `item.deleted` đánh dấu xoá. Sự kiện cho mục không có trong kho (trừ `item.created`) bị bỏ qua. Cursor chỉ tăng, bằng `seq` lớn nhất đã áp dụng. Trả về danh sách mục **mới với kho**, chưa đọc và còn hiển thị, để popup dùng (Phase 5).
  - `replaceAll(items:seq:)` cho đồng bộ đầu và đối chiếu: mục không có trong danh sách server bị bỏ; mục có thì nhận trạng thái server; cursor thành `max(cursor, seq)`. Không trả mục nào cho popup.
  - Sau mỗi phép áp dụng từ server, thao tác còn trong hàng đợi được áp lại lên kho, để thao tác chưa gửi của người dùng không bị trạng thái cũ ghi đè.
- `announce(_ items: [Item])` đặt thuộc tính quan sát được `announcement: Announcement?` (`serial` tăng dần, `items` mới nhất trước). Đây là chỗ gặp nhau giữa sync engine (Phase 3 gọi) và popup (Phase 5 quan sát), để hai phase không phải nối trực tiếp với nhau. Không lưu vào file.
- Hàng đợi (`PendingAction`: `id`, `itemId`, `.read(Bool)` hoặc `.delete`, `createdAt`):
  - `markRead(id)`, `markUnread(id)` (cho API nội bộ, UI M2 không dùng), `delete(id)` áp ngay vào kho và thêm vào hàng đợi.
  - Gộp: với cùng `itemId`, `delete` thay mọi thao tác trước; `read` mới thay `read` cũ; không thêm `read` sau `delete` (xoá thắng đã đọc, architecture §5).
  - `outcome(for: status)` là hàm thuần quyết định số phận thao tác sau khi gửi: 2xx hoặc 404 thì bỏ (404 nghĩa là mục đã bị xoá hoặc dọn hẳn, architecture §4.1); 400 thì bỏ và ghi log lỗi; 401, 403 thì giữ và báo dừng gửi; 5xx hoặc lỗi mạng thì giữ để thử lại.
- `popupSettings`: `disabledKinds: Set<String>`, `quietMode: Bool`. Chế độ yên lặng chỉ bật hoặc tắt bằng tay, bật tới khi người dùng tắt, lưu bền qua lần khởi động lại (operator trả lời câu hỏi 3, 2026-11-23). Mặc định mọi loại bật, yên lặng tắt (câu hỏi 5).

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/OSWidgetKit/`.

- Create: `Sources/OSWidgetKit/Model/Item.swift`, `Sources/OSWidgetKit/Model/Block.swift`, `Sources/OSWidgetKit/Model/ServerEvent.swift`
- Modify: `Sources/OSWidgetKit/Store/ItemStore.swift` (Phase 1 tạo khung rỗng với `ItemStore.live()`; phase này viết thân)
- Create: `Sources/OSWidgetKit/Store/PendingAction.swift`, `Sources/OSWidgetKit/Store/PopupSettings.swift`
- Create: `Tests/OSWidgetKitTests/ModelDecodingTests.swift`, `Tests/OSWidgetKitTests/StoreApplyTests.swift`, `Tests/OSWidgetKitTests/QueueTests.swift`
- Create: `Tests/OSWidgetKitTests/Fixtures/items.json`, `Tests/OSWidgetKitTests/Fixtures/events.json`

## Tasks & Steps

- [ ] Lấy một bản `GET /items` và một trang `GET /events?since=<seq gần cuối>` thật từ Worker đã deploy bằng token client, bỏ mọi giá trị nhạy cảm (chỉ giữ mục thử có `source: "acceptance"`), lưu làm fixture. Thêm tay một mục `kind: "weather"` (không tồn tại), một mục `vocab`, một mục `generic` có block lạ, một `item.created` với `item: null`.
- [ ] Mô hình và giải mã chịu lỗi.
- [ ] `ItemStore` với các phép áp dụng, lưu và nạp file.
- [ ] Hàng đợi và hàm `outcome(for:)`.
- [ ] Test (bảng dưới).

| Test | Kiểm |
|---|---|
| Giải mã fixture | `notification`, `generic` (block lạ bị bỏ), `vocab` thành `.unknown`, `kind` lạ thành `.unknown` nhưng giữ `title` và `summary`; `body` hỏng không làm hỏng mục |
| Áp dụng lại | Áp cùng một trang sự kiện hai lần cho kết quả giống một lần; không có mục trùng |
| Chồng lấn | Áp trang `since=n-5` sau trang `since=n` không đổi kết quả và cursor không lùi |
| Mục mới cho popup | Chỉ mục chưa có trong kho, chưa đọc, chưa hết hạn; mục được tạo rồi đọc trong cùng trang không được trả về |
| `item: null` | Bị bỏ qua, cursor vẫn tăng |
| Đối chiếu | Mục không còn trên server bị bỏ; cursor thành `max` |
| Hàng đợi | Xoá thắng đã đọc; đọc rồi bỏ đọc gộp thành một thao tác; thao tác chưa gửi được áp lại sau khi nhận `item.unread` từ server |
| `outcome(for:)` | 204, 404 bỏ; 400 bỏ kèm log; 401, 403 giữ và dừng; 500, 502, lỗi mạng giữ |
| Hết hạn | Mục có `expires_at` trong quá khứ không hiển thị và bị bỏ khỏi file khi ghi |
| Lưu bền | Ghi, nạp lại từ file cho cùng trạng thái; file hỏng thì kho bắt đầu rỗng với cursor `nil` (đồng bộ lại từ đầu) và ghi log |

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass, gồm mọi test trong bảng.
- Không file nào trong `Sources/` import `WidgetKit`: `git grep -n "import WidgetKit" apps/macos` rỗng.

## Risk Assessment

- PostgREST trả `created_at` có 6 chữ số lẻ giây; `ISO8601DateFormatter` mặc định không nhận. Dùng `Date.ISO8601FormatStyle` có phần lẻ giây và test bằng fixture thật.
- Ghi file đồng thời từ hai tiến trình chỉ xảy ra khi Giai đoạn 3 thêm widget ghi hàng đợi; M2 chỉ có app ghi. Ghi chú cho Giai đoạn 3: khi đó dùng `NSFileCoordinator` hoặc chuyển sang SQLite.
- `id` gửi lên server phải giữ nguyên dạng server trả (chữ thường); Worker trả 404 cho UUID chữ hoa (`plans/261123-0921-m1-server-supervisor/follow-ups.md`). Không chuẩn hoá `id`.

## Rollback

Xoá các file trong `Model/`, `Store/` và test của phase. Kho trên máy là `store.json` trong group container (hoặc Application Support): xoá file đó; app đồng bộ lại từ server ở lần chạy sau.
