---
phase: 4
title: "Giao diện widget và bố cục rút gọn theo loại"
status: completed
priority: P1
effort: "4h"
dependencies: [1, 2]
---

# Phase 4: Giao diện widget và bố cục rút gọn theo loại

## Goal

Widget `OSWidgetItems` cỡ vừa và cỡ lớn đọc kho dùng chung, hiện các mục mới nhất (mới nhất trên cùng) với bố cục rút gọn theo loại; loại chưa có bố cục hiện `title` và `summary`. Mỗi hàng chừa chỗ cho nút do Phase 5 thêm.

## Context

- Phụ thuộc thử nghiệm A: provider đọc file trong group container qua `StoreReader` và `ActionInbox` (Phase 2). Ở nhánh A trượt vì App Group, chỉ hàm lấy dữ liệu trong `ItemsProvider` đổi sang gọi localhost; view và snapshot giữ nguyên.
- `CardView` (`Cards/CardView.swift`) chọn view đầy đủ theo `CardView.Variant` (`notification`, `generic`, `fallback`); `FallbackCardView`, `CardHeader`, `CardFooter`, `URLPolicy` có sẵn. Bố cục rút gọn là bộ view riêng, nhỏ hơn, không tải ảnh (widget không tải ảnh mạng).
- Phối hợp Giai đoạn 4: plan.md, mục "Phối hợp với Giai đoạn 4". `vocab` hiện là `ItemContent.unknown` nên đi vào `.fallback`.
- Câu hỏi 2, 3, 5 (số mục mỗi cỡ, hiện mục đã đọc, bấm vào thân mục): theo đề xuất trừ khi operator trả lời khác.

## Requirements

**Bố cục rút gọn** (`OSWidgetKit/Sources/OSWidgetKit/Cards/Compact/`, SwiftUI thuần, không import WidgetKit):

- `public struct CompactCardView: View { init(item: Item, lines: Int = 2) }` và `public enum Variant { case notification, generic, fallback }` với `public nonisolated static func variant(for: ItemContent) -> Variant` dạng `switch` đủ trường hợp, không `default`.
- `notification`: `title` (một dòng, đậm khi chưa đọc), `summary` hoặc dòng đầu của `text` dạng chữ thường (không render markdown).
- `generic`: `title`, rồi dòng chữ của block `heading` hoặc `text` đầu tiên; bỏ ảnh, mã, danh sách.
- `fallback`: `title` và `summary` (FR-12, FR-17).
- Dòng phụ chung: `source` và thời gian bằng `Text(item.createdAt, style: .relative)` để hệ thống tự cập nhật, không cần reload.
- Mục đã đọc: chữ màu phụ, không đậm (câu hỏi 3).

**Kích thước** (`OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetSize.swift`):

- `public enum WidgetSize { case medium, large }` với `rowLimit` (3 và 6, câu hỏi 2) và `leadRowLines` (2 ở cỡ vừa, 4 ở cỡ lớn để thẻ rút gọn của Giai đoạn 4 có chỗ). `rowLimit` lớn nhất bằng `WidgetSnapshot.maxItems`.

**Widget** (`Widget/`):

- `ItemsProvider: TimelineProvider`: `getTimeline` đọc `StoreReader.read(location: try StoreLocation.appGroup())` và `ActionInbox(location:).pending()`, dựng `WidgetSnapshot.make`, trả một entry với `policy: .after(nextExpiry)` khi có hạn, ngược lại `.never`. Ghi `widget.timeline family=<medium|large> items=<n> unread=<n> top=<id hoặc none>` ở mức `notice`, category `widget` (Phase 3 và 6 dựa vào dòng này). `placeholder` và `getSnapshot` khi `context.isPreview` dùng ba mục mẫu cố định trong mã, không đọc file.
- `ItemsWidget: Widget`: `StaticConfiguration(kind: WidgetKind.items, provider: ItemsProvider())`, `supportedFamilies([.systemMedium, .systemLarge])`, tên "OS Widget", mô tả "Các mục mới nhất".
- `ItemsWidgetView`: đầu widget "OS Widget" và số chưa đọc; tối đa `rowLimit` hàng `ItemRow`, mục mới nhất trên cùng; trạng thái rỗng "Chưa có mục"; không đọc được kho thì "Mở OS Widget để đồng bộ"; `.containerBackground(.fill.tertiary, for: .widget)` như spike.
- `ItemRow`: `CompactCardView` cùng `ItemRowActions(item:)` ở cuối hàng. Phase 4 tạo `ItemRowActions` là view rỗng; Phase 5 viết thân.
- Bấm vào thân hàng không làm gì (câu hỏi 5): không đặt `widgetURL` hay `Link`.
- `OSWidgetWidgetBundle` (khung của Phase 1) chỉ chứa `ItemsWidget()`.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`.

- Modify: `Widget/OSWidgetWidgetBundle.swift`
- Create: `Widget/ItemsProvider.swift`, `Widget/ItemsWidget.swift`, `Widget/ItemsWidgetView.swift`, `Widget/ItemRow.swift`, `Widget/ItemRowActions.swift` (khung rỗng)
- Create: `OSWidgetKit/Sources/OSWidgetKit/Cards/Compact/CompactCardView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/Compact/CompactNotificationView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/Compact/CompactGenericView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/Compact/CompactFallbackView.swift`, `OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetSize.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/CompactCardTests.swift`

## Tasks & Steps

- [x] View rút gọn và `WidgetSize`, kèm `#Preview` cho từng loại (dùng fixture `items.json` có sẵn: `notification`, `generic` có block lạ, `vocab`, `weather`).
- [x] Provider, widget, view widget, hàng, khung nút.
- [x] Test (bảng dưới); build Debug không ký.

| Test | Kiểm |
|---|---|
| Biến thể | `notification` → `.notification`, `generic` → `.generic`, `vocab` và `weather` → `.fallback` |
| Dòng chữ rút gọn | `generic` lấy `heading` hoặc `text` đầu tiên, bỏ block lạ; `notification` không có `text` dùng `summary`; chuỗi markdown hiện như chữ thường |
| Số hàng | `WidgetSize.medium.rowLimit == 3`, `.large == 6`, cả hai ≤ `WidgetSnapshot.maxItems` |
| Dựng view | `ImageRenderer` dựng được `CompactCardView` cho mọi mục trong fixture mà không lỗi (kiểm không treo, không cần so ảnh) |

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass; `git grep -n "import WidgetKit" apps/macos/OSWidgetKit` rỗng.
- `xcodebuild … CODE_SIGNING_ALLOWED=NO build` thành công.
- Xem `#Preview` của widget trong Xcode ở hai cỡ (ảnh chụp đính vào báo cáo cook). Kiểm trên desktop thật ở Phase 6.

## Risk Assessment

- Widget có giới hạn bộ nhớ và thời gian dựng: không tải ảnh, không render markdown, tối đa 6 hàng.
- `Text(_:style: .relative)` trên macOS hiện chữ tiếng Anh nếu ngôn ngữ hệ thống là tiếng Anh; chấp nhận, giống danh sách.
- `StoreLocation.appGroup()` trong extension đọc `AppGroupID` từ `Info.plist` của extension (Phase 1); thiếu khoá thì hiện trạng thái "Mở OS Widget để đồng bộ" và ghi log, không crash.

## Rollback

Xoá các file mới, trả `OSWidgetWidgetBundle.swift` về khung của Phase 1. Không ảnh hưởng app.
