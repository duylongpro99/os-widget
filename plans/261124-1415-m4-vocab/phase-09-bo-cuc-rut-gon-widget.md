---
phase: 9
title: "Bố cục rút gọn vocab ở widget"
status: pending
priority: P2
effort: "2h"
dependencies: [8]
---

# Phase 9: Bố cục rút gọn `vocab` ở widget

Client. Phụ thuộc các phase widget của M3 (`plans/261124-1415-m3-widget/`): widget extension đọc kho dùng chung, và chỗ ánh xạ `kind` sang bố cục rút gọn. Chỉ mở khi các phase đó đã xong và đã merge vào `main`.

## Goal

Mục `vocab` trong widget hiện bằng bố cục rút gọn riêng thay cho `title` và `summary`, ở cả cỡ vừa và cỡ lớn (FR-12, FR-13).

## Context

- Roadmap Giai đoạn 4: "bố cục rút gọn ở widget". Roadmap Giai đoạn 3: "bố cục rút gọn cho từng loại" do M3 làm.
- `VocabContent` từ Phase 8 dùng lại để giải mã.
- Architecture §6: không có nút phát âm trong widget.
- Khi viết plan này, plan M3 chưa có; tên file và kiểu ánh xạ bố cục rút gọn lấy theo plan M3 lúc mở phase.

## Files to Create / Modify

- Modify: file bố cục rút gọn theo `kind` mà M3 tạo, chỉ thêm nhánh `vocab` (tên file theo plan M3)
- Create: view bố cục rút gọn `vocab` cạnh các bố cục của M3 (ví dụ `VocabCompactView.swift` trong cùng thư mục)
- Modify: test bố cục rút gọn của M3, thêm trường hợp `vocab`

## Thiết kế

- **Cỡ vừa** (một dòng mục trong danh sách widget): `word` đậm, `ipa` màu phụ, `pos`; dòng thứ hai là định nghĩa đầu tiên, tối đa 2 dòng.
- **Cỡ lớn**: như cỡ vừa, thêm ví dụ đầu tiên (1 dòng, nghiêng) và tối đa 3 từ đồng nghĩa; nếu mục `vocab` là mục mới nhất, cho phép hiện ngữ cảnh 2 dòng.
- Nội dung `vocab` không hợp lệ dùng bố cục dự phòng của M3.
- Nút đã đọc và xoá theo M3; không thêm nút mới.

## Tasks & Steps

- [ ] Đọc plan M3 và mã widget đã merge; xác định điểm ánh xạ.
- [ ] Thêm view và nhánh `vocab`.
- [ ] Test: mục `vocab` chọn bố cục `vocab`; `vocab` thiếu `ipa` chọn bố cục dự phòng.
- [ ] Kiểm bằng preview widget hai cỡ.

## Verification

- `swift test` pass.
- `xcodebuild` build app và widget extension thành công.

## Risk Assessment

- Bố cục của M3 không có điểm mở rộng theo `kind`: dừng và báo supervisor thay vì sửa phần chung của M3 (mục "Stop and ask" của plan).
- Định nghĩa dài làm vỡ bố cục: giới hạn dòng như trên.

## Rollback

Revert commit; mục `vocab` trong widget quay về `title` và `summary`.
