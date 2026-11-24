# Báo cáo review: bố cục rút gọn vocab ở widget

Nhánh `vocab-widget-compact` (97ec05f) đã review, sửa một điểm nhỏ và merge vào `main`.

## Kết quả kiểm
- `layout(for:lines:)` không vượt số dòng: hàng thường 1, hàng đầu cỡ vừa 2, hàng đầu cỡ lớn 4 (test quét `lines` 0...6).
- Từ, `ipa` và `pos` nằm một dòng với `lineLimit(1)`, dài thì bị cắt, không xuống dòng.
- Không có nút phát âm; `variant(for:)` và `detail(for:)` vẫn `switch` đủ trường hợp, không `default`; OSWidgetKit không `import WidgetKit`.
- Hàng đã đọc dùng cùng quy ước màu `.secondary`/`.tertiary` như các view rút gọn khác.
- Mutation: cho định nghĩa luôn chiếm 2 dòng thì `vocabLayoutPerRow` fail; đã revert.

## Phát hiện
- Nhỏ: `ipa` dài có thể ép từ bị cắt trước. Sửa bằng `layoutPriority(1)` cho từ (790623d).

## Ghi chú
- Ngữ cảnh chỉ hiện khi mục thiếu ví dụ hoặc đồng nghĩa (cỡ lớn 4 dòng đã dùng hết); `WidgetSize` giữ nguyên, theo quyết định của supervisor.
- Preview chưa chạy trong Xcode canvas.
