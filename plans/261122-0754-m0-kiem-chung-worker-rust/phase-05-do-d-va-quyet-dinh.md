---
phase: 5
title: "Đo D và quyết định"
status: completed
priority: P1
effort: "1.5h"
dependencies: [4]
---

# Phase 5: Đo D và quyết định

## Goal

Đo CPU và dung lượng của Worker Rust đã deploy bằng số liệu thật của Cloudflare, rồi quyết Rust hay TypeScript theo ngưỡng đã chốt.

## Ngưỡng (đã chốt với người dùng)

- **Đạt:** CPU p99 ≤ 5 ms ở cả `POST /items` và `GET /events`, **và** dung lượng sau nén nằm dưới hạn mức miễn phí ghi trong `reports/limits.md`.
- **Trượt:** một trong hai điều trên không đạt sau khi đã thử các bước tối ưu dung lượng.

## Files to Create / Modify

- Create: `scripts/measure-worker.sh`
- Create: `plans/261122-0754-m0-kiem-chung-worker-rust/reports/d-results.md`
- Chỉ khi trượt: `worker-ts/` (Worker TypeScript cùng hai endpoint)

## Tasks & Steps

- [x] `scripts/measure-worker.sh <url>`: đọc token từ biến môi trường `SPIKE_TOKEN`, gửi tuần tự 150 `POST /items` (title khác nhau, `dedupe_key` null) rồi 150 `GET /events?since=<seq gần cuối>`, và in số request trả lỗi.
- [x] Chạy script trên bản deploy. Lấy CPU p50 và p99 cho từng endpoint từ Workers Logs (trường CPU time của mỗi invocation), hoặc từ trang Metrics của Worker nếu Logs không cho tách theo endpoint. Ghi rõ đã lấy từ nguồn nào.
- [x] Ghi riêng CPU của request đầu tiên sau khi deploy (cold start), để trả lời câu hỏi CPU khởi động Wasm có bị tính hay không.
- [x] Nếu dung lượng vượt hạn mức: thử `wasm-opt -Oz` (cài qua `brew install binaryen` nếu `worker-build` chưa tự chạy) và bỏ phụ thuộc không cần thiết, rồi đo lại. *(Không cần: 563.08 KiB chưa nén, dưới hạn mức 64 MiB.)*
- [x] Ghi `reports/d-results.md`: n theo từng endpoint, CPU p50/p99, CPU cold start, dung lượng tổng và gzip, nguồn số liệu, phiên bản `worker` crate và wrangler, quyết định cuối cùng.
- [x] Chỉ khi trượt: viết `worker-ts/` với cùng hai endpoint, cùng token tạm và cùng schema; deploy, chạy lại script và ghi số đo vào `d-results.md`. Crate `envelope` vẫn giữ cho CLI dùng. *(Không làm: Rust trượt ngưỡng nhưng operator quyết định giữ Rust ngày 2026-11-22, xem `reports/d-results.md`.)*
- [x] Xoá dữ liệu thử trong `items` và `events` sau khi đo xong.

## Verification

- `reports/d-results.md` có đủ các số ở trên, n ≥ 100 cho mỗi endpoint, và một dòng quyết định "Rust" hoặc "TypeScript" kèm lý do so với ngưỡng.
- Số request lỗi trong script là 0, hoặc có giải thích.

## Risk Assessment

- CPU biến động mạnh giữa các lần chạy (ví dụ p99 lệch hơn 2 lần giữa hai lần đo): dừng và hỏi người dùng (điều kiện dừng của plan).
- Nhánh TypeScript đòi đổi API hoặc schema: dừng và hỏi.
- p99 nằm trong khoảng 5–10 ms: theo ngưỡng đã chốt thì vẫn là trượt. Ghi rõ con số để người dùng có thể xem lại ngưỡng nếu muốn.
