---
phase: 1
title: "Kiểm độ phủ trường của API từ điển"
status: completed
priority: P1
effort: "0.5h"
dependencies: []
---

# Phase 1: Kiểm độ phủ trường của API từ điển

## Goal

Biết Free Dictionary API cung cấp đủ trường của body `vocab` tới mức nào trước khi viết mã nạp, theo yêu cầu đi kèm quyết định D4.

## Context

Quyết định D4: nạp dùng `https://api.dictionaryapi.dev` và sách `.txt`. Architecture §4.4 ghi "Chưa kiểm chứng: API từ điển nào đủ trường". Bước này đã chạy khi viết plan (20 request GET chỉ đọc), nên cook không phải làm lại.

## Files to Create / Modify

- Create: `plans/261124-1415-m4-vocab/reports/api-coverage.md` (bảng số đo)
- Create: `plans/261124-1415-m4-vocab/reports/api-samples/<word>.json` (20 đầu ra thô, dùng làm fixture ở Phase 5)

## Tasks & Steps

- [x] Gọi `GET /api/v2/entries/en/<word>` cho 20 từ (18 từ đáng học, 2 dạng biến tố), tuần tự, cách nhau 0,4 giây.
- [x] Đếm số từ có `ipa`, `pos`, `definition`, `example`, `synonyms`, `antonyms`, `audio`.
- [x] Ghi kết quả và hệ quả vào `reports/api-coverage.md`.

## Kết quả

20/20 trả 200. `ipa` 17/20 (`phonetic` gốc 14, thêm 3 từ `phonetics[].text`), `pos` 20/20, `definition` 20/20, `example` 9/20, `synonyms` 14/20, `antonyms` 8/20, `audio` 15/20 (đều `https://`), `context` 0/20. Đủ trường bắt buộc: 17/20. Từ bị bỏ: `resilient`, `vindicate`, `lanterns` (thiếu IPA). Nghĩa đầu tiên không luôn là nghĩa chính (`candid`, `lucid`, `ephemeral`).

## Verification

- `ls plans/261124-1415-m4-vocab/reports/api-samples/*.json | wc -l` là 20.
- Mọi file mẫu là JSON hợp lệ: `for f in plans/261124-1415-m4-vocab/reports/api-samples/*.json; do jq -e 'type == "array"' "$f" >/dev/null || echo "$f"; done` không in gì.

## Risk Assessment

- API không có SLA và có thể đổi định dạng: Phase 5 dùng các file mẫu làm fixture, nên thay đổi định dạng lộ ra ở lần nạp thật (Phase 7) dưới dạng nhiều từ bị bỏ, không làm hỏng dữ liệu.

## Rollback

Không có thay đổi mã hay dữ liệu.
