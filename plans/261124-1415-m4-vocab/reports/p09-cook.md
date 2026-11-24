# Báo cáo cook: bố cục rút gọn vocab ở widget

Nhánh `vocab-widget-compact`, commit tính năng `b7567e0` (trên `main` tại `641deb2`).

## Đã làm
- `CompactCardView.Variant.vocab`; `variant(for:)` ánh xạ `.vocab` sang nó. Nội dung `vocab` không giải mã được (thiếu `ipa`, `word`, `pos` hoặc nghĩa) đã thành `.unknown` ở tầng mô hình nên dùng bố cục dự phòng.
- `CompactVocabView`: dòng từ (từ đậm, `ipa` màu phụ, `pos`), rồi định nghĩa đầu tiên (tối đa 2 dòng), ví dụ đầu (1 dòng, nghiêng), tối đa 3 từ đồng nghĩa, ngữ cảnh (tối đa 2 dòng). Không có nút phát âm.
- `CompactVocabView.layout(for:lines:)` chia số dòng theo thứ tự ưu tiên và không bao giờ vượt `lines`; có test.

## Kiểm
- `swift test`: 188 pass (184 + 4 mới). `cargo test --workspace`: 187 pass.
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` với derivedDataPath ngoài repo: BUILD SUCCEEDED.
- `git grep "import WidgetKit" apps/macos/OSWidgetKit`: rỗng. Không còn tiến trình xcodebuild hay swift-build.
- Preview hai cỡ (hàng thường, hàng đầu cỡ vừa, hàng đầu cỡ lớn) có trong `CompactCardPreviews.swift`; chưa chạy Xcode canvas.

## Khác với phase file
- Cỡ lớn: hàng đầu có 4 dòng (`WidgetSize.large.leadRowLines`). Định nghĩa 2 dòng, ví dụ 1, đồng nghĩa 1 đã dùng hết, nên ngữ cảnh chỉ hiện khi mục thiếu ví dụ hoặc đồng nghĩa. View không biết mục có phải mới nhất hay không, chỉ biết số dòng, nên "mới nhất" được hiểu là hàng đầu có nhiều dòng. Giữ trong số dòng của `WidgetSize` theo ghi chú review.
- Phase file nói sửa `CompactCardView.swift` và test; thêm `CompactCardPreviews.swift` (cùng thư mục) để preview thay đoạn "vocab fallback".
