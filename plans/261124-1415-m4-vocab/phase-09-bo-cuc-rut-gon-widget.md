---
phase: 9
title: "Bố cục rút gọn vocab ở widget"
status: pending
priority: P2
effort: "2h"
dependencies: [8]
---

# Phase 9: Bố cục rút gọn `vocab` ở widget

Client. Phụ thuộc Phase 4 của M3 ([Giao diện widget và bố cục rút gọn theo loại](../261124-1415-m3-widget/phase-04-giao-dien-widget-va-bo-cuc-rut-gon.md)), vốn cần Phase 1 và 2 của M3, và Phase 8 của plan này. Chỉ mở khi các phase đó đã merge vào `main`.

## Goal

Mục `vocab` trong widget hiện bằng bố cục rút gọn riêng thay cho `title` và `summary`, ở cả cỡ vừa và cỡ lớn (FR-12, FR-13).

## Context

- Roadmap Giai đoạn 4: "bố cục rút gọn ở widget". Roadmap Giai đoạn 3: "bố cục rút gọn cho từng loại" do M3 làm.
- `VocabContent` từ Phase 8 dùng lại để giải mã.
- Architecture §6: không có nút phát âm trong widget.
- Plan M3 (mục "Phối hợp với Giai đoạn 4"): `CompactCardView` trong `OSWidgetKit/Sources/OSWidgetKit/Cards/Compact/` chọn view theo `CompactCardView.Variant`, ánh xạ từ `ItemContent` bằng `switch` đủ trường hợp; cỡ lớn có `WidgetSize.large.leadRowLines` để thẻ `vocab` rút gọn có chỗ. Đây là file duy nhất của M3 mà M4 sửa.

## Files to Create / Modify

Dưới `apps/macos/OSWidgetKit/`:

- Modify: `Sources/OSWidgetKit/Cards/Compact/CompactCardView.swift` (`Variant.vocab`, `case .vocab` ở `variant(for:)` thay cho ánh xạ tạm sang `.fallback` của Phase 8)
- Create: `Sources/OSWidgetKit/Cards/Compact/CompactVocabView.swift`
- Modify: `Tests/OSWidgetKitTests/CompactCardTests.swift` (thêm trường hợp `vocab`)

## Thiết kế

- **Cỡ vừa** (một dòng mục trong danh sách widget): `word` đậm, `ipa` màu phụ, `pos`; dòng thứ hai là định nghĩa đầu tiên, tối đa 2 dòng.
- **Cỡ lớn**: như cỡ vừa, thêm ví dụ đầu tiên (1 dòng, nghiêng) và tối đa 3 từ đồng nghĩa; nếu mục `vocab` là mục mới nhất, cho phép hiện ngữ cảnh 2 dòng.
- Nội dung `vocab` không hợp lệ dùng bố cục dự phòng của M3.
- Nút đã đọc và xoá theo M3; không thêm nút mới.

## Tasks & Steps

- [ ] Đọc `CompactCardView.swift` và `WidgetSize.swift` đã merge.
- [ ] Thêm view và nhánh `vocab`.
- [ ] Test: mục `vocab` chọn bố cục `vocab`; `vocab` thiếu `ipa` chọn bố cục dự phòng.
- [ ] Kiểm bằng preview widget hai cỡ.

## Verification

- `swift test` pass.
- `xcodebuild` build app và widget extension thành công.

## Risk Assessment

- `CompactCardView` khi merge khác mô tả của plan M3 (không có `Variant` hoặc `switch` đủ trường hợp): dừng và báo supervisor thay vì sửa phần chung của M3 (mục "Stop and ask" của plan).
- Định nghĩa dài làm vỡ bố cục: giới hạn dòng như trên.

## Rollback

Revert commit; mục `vocab` trong widget quay về `title` và `summary`.
