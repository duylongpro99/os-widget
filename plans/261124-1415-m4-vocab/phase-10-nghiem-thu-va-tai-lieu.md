---
phase: 10
title: "Nghiệm thu PRD §10.5 và cập nhật tài liệu"
status: completed
priority: P1
effort: "2h"
dependencies: [7, 8, 9]
---

# Phase 10: Nghiệm thu PRD §10.5 và cập nhật tài liệu

Client và tài liệu.

## Goal

Cài app có thẻ `vocab` lên MacBook, kiểm PRD §10.5 với một mục `vocab` thật do cron gửi, và ghi những gì M4 đã làm vào architecture, roadmap và PRD.

## Context

- Cài app như Phase 6 của M2: build Release với `-allowProvisioningUpdates`, copy vào `/Applications` (`apps/macos/README.md`).
- Bộ từ thật đã nạp ở Phase 7 (G3), có từ lấy từ sách nên có `context`.

## Files to Create / Modify

- Create: `plans/261124-1415-m4-vocab/reports/acceptance.md`
- Modify: `docs/architecture.md`, `docs/roadmap.md`, `docs/prd.md`

## Tasks & Steps

### Nghiệm thu

- [x] Cài bản app mới lên MacBook; `scripts/acceptance-menu-bar.sh` (phần tự động) vẫn pass. Bằng chứng: cài lại 2026-11-27 21:53:57 từ `5fe3c0a`; `acceptance-menu-bar.sh 1` PASS, `latency_ms=549`.
- [x] **PRD §10.5.** Đợi (hoặc tạm đặt `vocab_interval_minutes` nhỏ, bước **[operator]** như G4 của Phase 7) một mục `vocab` của một từ lấy từ sách có `audio_url`: Bằng chứng: thẻ publish tay `ubiquitous` (đủ trường, có `audio_url`) và `meander` (không có `audio_url`), D32 và D34; `source=audio` 4 lần, `source=speech` 1 lần, `read_at` rỗng. Nút được bấm trong danh sách, không có lần bấm trên popup trong log; không đợi thẻ cron (D35). Không đổi `settings`.
  - popup hiện từ, phiên âm, từ loại, nghĩa, ví dụ, ngữ cảnh, đồng nghĩa và trái nghĩa (ghi trường nào có trong `entry` của từ đó), và nút phát âm;
  - bấm nút phát âm phát `audio_url` (log `pronounce.play source=audio`), mục vẫn chưa đọc;
  - mở danh sách, thẻ giống popup, bấm phát âm cũng phát;
  - một từ không có `audio_url` (ví dụ publish tay một envelope `vocab` không có `audio_url` bằng `os-widget publish --file`) phát bằng bộ đọc hệ thống (`source=speech`).
- [x] Widget (Phase 9): mục `vocab` hiện bố cục rút gọn ở cỡ vừa và cỡ lớn. Bằng chứng: D33; `widget.timeline` medium và large với thẻ thử trên cùng 21:59:15.
- [x] Ghi kết quả, ảnh chụp mô tả bằng chữ và dòng log vào `reports/acceptance.md`. Bằng chứng: [reports/acceptance.md](./reports/acceptance.md).

### Tài liệu

- [x] `docs/architecture.md`: Bằng chứng: §3.2, §4.1, §4.4, §6 (mục mới "Thẻ từ vựng đã làm"), §8, dòng đầu.
  - §3.2: `ipa`, `pos` không rỗng, `word` một dòng.
  - §4.1: endpoint `POST /vocab/words` (token publish, body, giới hạn 50, lỗi `invalid vocab`, 200 `{"stored"}`).
  - §4.4: `vocab_upsert`, `vocab_tick` và các bước của nó; các khoá `settings` và giá trị đã chốt; nhịp cron `*/5`, bù 1 phút; quy tắc giữ `context`; ánh xạ Free Dictionary API; chọn từ trong sách; bỏ dòng "Chưa kiểm chứng: API từ điển nào…" và ghi độ phủ 17/20.
  - §6: phát âm đã làm (`Pronouncer`, log category `audio`).
  - §8: CPU đo được của lần chạy cron và của `POST /vocab/words`.
  - Dòng "Cập nhật" và "Trạng thái" ở đầu file.
- [x] `docs/roadmap.md`: mục "Kết quả" của Giai đoạn 4 với từng tiêu chí và đường dẫn tới hai báo cáo nghiệm thu; chuyển câu 1 của "Việc cần quyết định" sang "Đã chốt" (Free Dictionary API và `.txt`, EPUB để sau). Bằng chứng: Giai đoạn 4 "Kết quả"; "Đã chốt"; thêm kết quả đêm ngủ máy của Giai đoạn 2.
- [x] `docs/prd.md` §11 câu 1: chốt API từ điển và định dạng sách. Bằng chứng: §11 câu 1.

## Verification

- `reports/acceptance.md` có kết quả từng gạch đầu dòng PRD §10.5.
- Liên kết trong docs đã sửa trỏ đúng; mọi khẳng định mới khớp với mã và hai báo cáo nghiệm thu.
- `cargo test --workspace`, `swift test` pass trên `main`.

## Risk Assessment

- Từ do cron chọn ngẫu nhiên có thể thiếu `antonyms` (API có ở 8/20 từ): kiểm "hiện đủ trường" theo trường có trong `entry`, và dùng thêm một envelope publish tay có đủ mọi trường để kiểm bố cục khi mọi trường cùng có.
- Profile ký hết hạn trước khi kiểm: theo nhánh build lại của M2.

## Rollback

Tài liệu: revert commit. App: cài lại bản trước từ commit `2f7bf2e`.
