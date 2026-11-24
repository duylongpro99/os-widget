# Báo cáo review Phase 4: Giao diện widget và bố cục rút gọn theo loại

Session `m3-widget-p04-review`. Nhánh `widget-items-ui` (head `bd90272`, tách từ main `8e229c3`) đã merge vào main bằng `--no-ff` ở `d5569ca`. Không có phát hiện nào cần sửa mã, nên nhánh không có commit sửa nào.

## Kết luận

Nhánh làm đúng file phase và các quyết định của supervisor (cỡ vừa 3 hàng, cỡ lớn 6 hàng với hàng đầu cao hơn, số chưa đọc ở đầu, mục đã đọc làm mờ, bấm thân hàng không làm gì, `ItemRowActions` rỗng chờ Phase 5). Các điểm lệch của cook đã được supervisor chấp nhận và mã khớp với chúng.

## Những gì đã kiểm

| Mục | Kết quả |
|---|---|
| `CompactCardView.variant(for:)` | `switch` đủ ba case của `ItemContent` (`notification`, `generic`, `unknown`), không có `default`. M4 thêm `.vocab` thì không biên dịch được tới khi xử lý. Loại lạ đi vào `.fallback` (title và summary). |
| Provider: mới nhất trên cùng, phủ hộp thư | `ItemsProvider.entry` gọi `WidgetSnapshot.make(items:pending:now:limit:)` với `ActionInbox.pending()`: mục chờ xoá bị ẩn, mục chờ đọc có `readAt` nên view làm mờ; sắp xếp mới nhất trước (hoà thì theo id). |
| Chính sách timeline | `.after(nextExpiry)` khi có hạn, ngược lại `.never`. |
| Log | `widget.timeline` chỉ có family, số đếm và id; `widget.store_unavailable` chỉ có mô tả lỗi vị trí. Không ghi nội dung mục. Mức `notice` nên `log show` giữ (sẽ là `messageType: Default`). |
| Khớp với `scripts/widget-reload-count.sh` (nhánh `widget-reload-policy`) | Khớp. Script lọc subsystem `local.oswidget.app`, category `widget`, và dòng bắt đầu bằng `widget.timeline `; provider ghi đúng `Logger(subsystem: "local.oswidget.app", category: "widget")` và chuỗi `widget.timeline family=… items=… unread=… top=…`, giống dòng trong `scripts/testdata/widget-log-sample.ndjson`. Khi không đọc được App Group vẫn ghi dòng `items=0 top=none`. |
| `OSWidgetKit` không import WidgetKit | `git grep "import WidgetKit" apps/macos/OSWidgetKit` rỗng. |
| Test là thật | Đổi số hàng (cỡ vừa 6, cỡ lớn 3) trong `WidgetSize.swift`: suite "Compact cards" thất bại với 2 issue ở `rowLimitsPerSize`. Đã hoàn nguyên, worktree sạch. |

## Kiểm trên main sau merge

- `cd apps/macos/OSWidgetKit && swift test`: 158 test trong 17 suite pass (Phase 3 chưa merge).
- `cargo test --workspace`: 151 pass.
- `xcodegen generate` rồi `xcodebuild -scheme OSWidget -configuration Debug -derivedDataPath <scratchpad> CODE_SIGNING_ALLOWED=NO build`: `BUILD SUCCEEDED`.
- `pgrep -fl "xcodebuild|swift-build"` rỗng khi kết thúc.

## Ghi chú, không chặn

1. **Cỡ vừa vừa khít ba hàng.** Hàng đầu cỡ vừa được 2 dòng chi tiết (`leadRowLines`), nên khi chi tiết dài SwiftUI phải nén. Cách sửa rẻ nếu Phase 6 thấy tràn trên desktop thật: đặt `WidgetSize.medium.leadRowLines` về 1 (một dòng trong `WidgetSize.swift`, test `leadRowLines >= rowLines` vẫn đúng; test `large > medium` vẫn đúng). Không đổi trong review vì file phase ghi 2 dòng cho cỡ vừa; để Phase 6 quyết theo ảnh thật.
2. Việc làm mờ mục đã đọc không có test riêng (là kiểu chữ của view, cần so ảnh mới kiểm được). Phần dữ liệu dẫn tới làm mờ (chờ đọc thành có `readAt`) đã có test của Phase 2.
3. `ItemsSamples.snapshot` tính `Date()` một lần khi nạp, nên thời gian tương đối của mẫu trong thư viện widget cũ dần. Chỉ ảnh hưởng mẫu, không đáng sửa.

## Dọn dẹp

Trạng thái Phase 4 đã đổi sang Completed trong `plan.md` và file phase. Worktree `/Users/onedayin20902/personal/os-widget-wt/widget-items-ui` đã gỡ và nhánh `widget-items-ui` đã xoá. Không push.

## Câu hỏi còn mở

Không có.
