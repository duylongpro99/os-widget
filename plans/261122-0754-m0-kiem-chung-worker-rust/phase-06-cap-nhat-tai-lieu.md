---
phase: 6
title: "Cập nhật tài liệu"
status: completed
priority: P2
effort: "1h"
dependencies: [3, 5]
---

# Phase 6: Cập nhật tài liệu

## Goal

Đưa kết quả D, hạn mức đã tra và thứ tự giai đoạn mới vào tài liệu dự án, để Giai đoạn 1 bắt đầu trên một thiết kế đã được kiểm chứng.

## Files to Create / Modify

- Modify: `docs/architecture.md`
- Modify: `docs/roadmap.md`

## Tasks & Steps

- [x] `architecture.md` §8: thay "Chưa đo với Rust" ở dòng Worker CPU bằng số p50/p99 đã đo; thêm dòng dung lượng Worker kèm hạn mức.
- [x] `architecture.md` §9: cập nhật dòng rủi ro `workers-rs` thành đã kiểm chứng (kèm kết quả) hoặc ghi rõ đã chuyển sang TypeScript.
- [x] `architecture.md` §4.4: thay "Chưa kiểm chứng: hạn mức Cron Trigger" bằng con số trong `reports/limits.md`.
- [x] Nếu D trượt: sửa §2 (dòng Server) và §4.2 (bố cục mã) cho Worker TypeScript, giữ nguyên API và schema. Không áp dụng: D trượt nhưng operator quyết định giữ Rust, nên §2 và §4.2 vẫn ghi Rust.
- [x] `roadmap.md`: sửa bảng tổng quan để Giai đoạn 1 chỉ phụ thuộc D; A và B chặn Giai đoạn 2 và 3; C chặn Giai đoạn 2. Ở mục Giai đoạn 0, ghi kết quả D và trạng thái A (đang chạy, ngày bắt đầu, ngày kiểm tra ngày 8).
- [x] Cập nhật dòng "Cập nhật:" ở đầu hai file thành ngày sửa.

## Verification

- `grep -n "Chưa đo với Rust" docs/architecture.md` không còn kết quả.
- `grep -n "Chưa kiểm chứng: hạn mức Cron" docs/architecture.md` không còn kết quả.
- Mọi số trong tài liệu khớp với `reports/d-results.md` và `reports/limits.md`.
- Liên kết giữa `prd.md`, `architecture.md` và `roadmap.md` vẫn đúng.
