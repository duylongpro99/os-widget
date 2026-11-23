---
phase: 4
title: "Thanh menu, danh sách và view thẻ"
status: completed
priority: P1
effort: "6h"
dependencies: [2]
---

# Phase 4: Thanh menu, danh sách và view thẻ

## Goal

Icon thanh menu có dấu báo chưa đọc, bấm mở danh sách mục mới nhất trên cùng với phân biệt đã đọc và chưa đọc, thao tác đã đọc và xoá, view thẻ cho `notification`, `generic` và dự phòng cho loại lạ, menu cài đặt popup, và app tự chạy khi đăng nhập.

## Context

- Không phụ thuộc thử nghiệm A hay B. Ràng buộc từ B: view thẻ nằm trong `OSWidgetKit` để widget hoặc cửa sổ desktop Giai đoạn 3 dùng lại.
- PRD: FR-5 (icon, không Dock, chạy khi đăng nhập), FR-9 (danh sách, dấu báo), FR-10b (mục mới khi danh sách đang mở), FR-10c (nút bật tắt theo loại, chế độ yên lặng), FR-14, FR-16, FR-17, FR-18 (đã đọc và xoá từ danh sách).
- Architecture §6: status item, card renderer, `SMAppService`; §7: markdown không render HTML thô, liên kết chỉ mở khi bấm, ảnh chỉ qua HTTPS.
- Ghi chú từ review M1 (`plans/261123-0921-m1-server-supervisor/follow-ups.md`): envelope chỉ kiểm tiền tố URL, nên `https://` không có host vẫn lọt qua server. Client phải tự kiểm URL có host trước khi mở hoặc tải.
- Làm song song được với Phase 3 và 5 sau Phase 2.

## Requirements

**Status item** (`App/MenuBar/MenuBarController.swift`, chữ ký từ Phase 1):

- `NSStatusItem` với SF Symbol (ví dụ `tray`), thêm chấm báo khi `store.unreadCount > 0` (đổi sang biến thể `tray.full` hoặc vẽ chấm; chọn một và giữ nhất quán ở chế độ sáng và tối).
- Bấm trái mở danh sách trong `NSPopover` neo vào nút icon (người dùng chủ động mở nên popover được phép kích hoạt app). Bấm phải mở menu: các nút bật tắt popup theo loại (`notification`, `generic`, `vocab`, cộng mọi `kind` khác đang có trong kho), một công tắc "Chế độ yên lặng" (có dấu tích khi bật; bật tới khi tắt, không có lựa chọn thời hạn), "Mở khi đăng nhập", "Cài đặt…", "Thoát".
- `anchorRect()` trả khung của nút icon trên màn hình (`button.window.convertToScreen(button.frame)`), `nil` khi không lấy được. `isListOpen` đúng khi popover đang hiện. Đây là hai thứ Phase 5 dùng.

**Danh sách** (`App/MenuBar/ItemListView.swift`):

- Mục hiển thị của kho, mới nhất trên cùng; mục chưa đọc in đậm kèm chấm, mục đã đọc chữ mờ hơn.
- Bấm vào thẻ: đánh dấu đã đọc và mở `url` bằng `NSWorkspace.shared.open` nếu có và hợp lệ (FR-10a). Mỗi thẻ có nút "Đã đọc" (ẩn khi đã đọc) và "Xoá"; mọi thao tác đi qua `store.markRead` và `store.delete` của Phase 2, rồi kích hoạt một vòng sync để gửi hàng đợi ngay.
- Mục mới vào khi danh sách đang mở: chèn lên đầu và nổi bật (nền nhấn) trong vài giây (FR-10b). Nhận biết bằng `store.announcement` đổi trong lúc popover mở.
- Danh sách rỗng: dòng chữ "Chưa có mục nào".

**View thẻ** (`OSWidgetKit/Sources/OSWidgetKit/Cards/`):

- `CardView(item:)` chọn view theo `item.content`; thêm `kind` mới chỉ cần thêm một case và một view (NFR-6).
- `NotificationCardView`: `title`, `summary`, `body.text` dạng markdown nội dòng, `source`, thời gian tương đối từ `created_at`, chỉ báo có liên kết (FR-14).
- `GenericCardView`: render từng block (FR-16): `heading` chữ lớn; `text` markdown; `fields` hai cột nhãn và giá trị; `list` có hoặc không đánh số; `image` qua `AsyncImage`, chỉ khi URL là `https` và có host, giới hạn chiều cao; `code` chữ đơn cách, cuộn ngang; `link` nút mở URL. Block `.unsupported` bị bỏ qua.
- `FallbackCardView`: `title`, `summary`, `source`, thời gian; dùng cho `.unknown`, gồm cả `vocab` ở M2 (FR-17). Không báo lỗi.
- Markdown qua `AttributedString(markdown:options:)` với `interpretedSyntax: .inlineOnlyPreservingWhitespace`; HTML trong chuỗi hiện nguyên văn như text. Liên kết trong markdown chỉ mở khi bấm và chỉ với `http`, `https`.
- `URLPolicy.isOpenable(_:)` và `URLPolicy.isLoadable(_:)` (hàm thuần): có scheme đúng và host không rỗng.
- Thẻ dùng chung kích thước và kiểu chữ cho danh sách và popup (Phase 5 nhúng `CardView`).

**Chạy khi đăng nhập** (`App/LaunchAtLogin.swift`): `SMAppService.mainApp.register()` và `unregister()`; trạng thái hiện ở menu lấy từ `SMAppService.mainApp.status`. Lần chạy đầu bật sẵn (FR-5); người dùng tắt được.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`.

- Modify: `App/MenuBar/MenuBarController.swift` (khung từ Phase 1)
- Create: `App/MenuBar/ItemListView.swift`, `App/MenuBar/StatusMenu.swift`, `App/LaunchAtLogin.swift`
- Create: `OSWidgetKit/Sources/OSWidgetKit/Cards/CardView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/NotificationCardView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/GenericCardView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/FallbackCardView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/URLPolicy.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/Markdown.swift`
- Create: `OSWidgetKit/Tests/OSWidgetKitTests/CardsTests.swift`

## Tasks & Steps

- [ ] `URLPolicy` và `Markdown`, test trước: `https://` không host bị từ chối; `javascript:`, `file:` bị từ chối; `http://example.com` mở được nhưng không tải ảnh được; chuỗi có `<script>` hiện nguyên văn.
- [ ] Ba view thẻ và `CardView`; test chọn view: `.unknown` (gồm `kind` lạ và `vocab`) ra `FallbackCardView`.
- [ ] Preview SwiftUI cho từng view với fixture của Phase 2 để soát giao diện sáng và tối.
- [ ] `MenuBarController`: icon, chấm báo, popover, menu chuột phải, `anchorRect()`, `isListOpen`.
- [ ] `ItemListView` với thao tác và nổi bật mục mới.
- [ ] `LaunchAtLogin` và mục menu.

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass, gồm `CardsTests`.
- App build được. Kiểm bằng tay với Worker thật, mỗi lần publish bằng `os-widget publish … --ttl 3600`:
  - Publish `notification` có `--link https://example.com`: chấm báo hiện; danh sách có mục ở đầu, in đậm; bấm thẻ mở trình duyệt và mục thành đã đọc; chấm báo tắt khi hết mục chưa đọc.
  - Publish `generic` bằng `--file` với mọi loại block và một block `type` lạ: block lạ không hiện, phần còn lại hiện đúng.
  - Publish `vocab` bằng `--file`: thẻ dự phòng hiện `title` và `summary`.
  - Xoá một mục: biến khỏi danh sách; `GET /items` không còn mục đó.
  - Bật "Mở khi đăng nhập", đăng xuất rồi đăng nhập lại: icon có mặt; System Settings > General > Login Items liệt kê OS Widget.

## Risk Assessment

- `NSPopover` trong app `.accessory` có thể không nhận bàn phím; danh sách không cần gõ phím nên chấp nhận.
- `SMAppService.mainApp.register()` đòi app nằm ở vị trí ổn định (ví dụ `/Applications`); bản chạy từ DerivedData có thể đăng ký sai đường dẫn. Kiểm chạy khi đăng nhập trên bản đã copy vào `/Applications` (Phase 6).
- Thẻ quá dài làm popover cao quá màn hình: giới hạn chiều cao danh sách và cho cuộn.

## Rollback

Trả `MenuBarController.swift` về khung của Phase 1, xoá các file còn lại của phase. Nếu đã bật chạy khi đăng nhập, tắt ở menu trước (hoặc gỡ ở System Settings > Login Items).

## Ghi chú

- Quyết định của operator (2026-11-23, khoảng 21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Phase này chỉ kiểm bằng `swift test` và build Debug không ký; app chưa chạy, `SMAppService` chưa bao giờ được gọi.
- Bấm liên kết trong thẻ (block `link` hoặc liên kết markdown): chỉ mở đúng liên kết đó nếu `URLPolicy.isOpenable` cho phép và đánh dấu mục đã đọc; không chạy thao tác bấm thẻ và không mở `url` của mục. Làm qua `View.onCardClick(tap:link:)` trong `OSWidgetKit` (`OpenURLAction` trong environment, thao tác bấm thẻ bị bỏ khi cùng cú bấm đã mở liên kết). Phase 5 nên dùng cùng modifier cho thẻ trong popup.
- Không có thông báo sync: Phase 3 tự sync khi `ItemStore.queue` có thao tác mới. Phase 4 sở hữu `Notification.Name.openItemListRequested` (`"local.oswidget.open-item-list"`); `isListOpen` tính từ `popover.isShown`.
- Lần chạy đầu chỉ ghi cờ "đã cấu hình" khi đăng ký chạy khi đăng nhập thành công hoặc đang chờ người dùng duyệt; đăng ký lỗi thì thử lại ở lần chạy sau.
- Hoãn tới Phase 6 (cần app chạy): mọi mục kiểm bằng tay ở Verification; mục mới nổi bật khi danh sách đang mở; menu chuột phải và các dấu tích; giao diện sáng và tối; bấm liên kết trong thẻ chỉ mở liên kết đó; bấm icon khi popover đang mở thì đóng chứ không mở lại; chạy khi đăng nhập trên bản ở `/Applications`.
- Báo cáo: [cook](../reports/cook-261123-m2-p04.md), [review](../reports/review-261123-m2-p04.md).
