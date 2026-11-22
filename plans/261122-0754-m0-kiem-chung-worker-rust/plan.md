---
title: "M0: kiểm chứng Worker Rust và khởi động thử nghiệm A"
description: "Hoàn thành thử nghiệm D trên khung Rust thật của Giai đoạn 1 và khởi động thử nghiệm A song song, để vào Giai đoạn 1 ngay khi D có kết quả."
status: in-progress
priority: P1
effort: 9.5h
tags: [infra, backend, experimental]
blockedBy: []
blocks: []
created: 2026-11-22
---

# M0: kiểm chứng Worker Rust và khởi động thử nghiệm A

## Overview

Hoàn thành thử nghiệm D của Giai đoạn 0 (`docs/roadmap.md`) trên khung Rust thật của Giai đoạn 1 và khởi động thử nghiệm A song song, để vào Giai đoạn 1 ngay khi D có kết quả. Phạm vi lấy từ lời khuyên `ak-advise` đã được xác nhận trong phiên `m0-advise`.

## Done means

1. Repo `os-widget` đã `git init`.
2. Cargo workspace có crate `envelope` (chỉ `notification`) và crate `worker` deploy lên gói miễn phí của Cloudflare; `POST /items` ghi vào Supabase qua PostgREST và `GET /events?since=0` trả về mục đó.
3. Đã đo ít nhất 100 request mỗi endpoint trên bản deploy, ghi CPU p50/p99 và dung lượng sau nén.
4. Đã quyết Rust (p99 ≤ 5 ms ở cả hai endpoint và dung lượng trong hạn mức) hoặc TypeScript, ghi vào `docs/architecture.md` §8/§9 kèm hạn mức Cron Trigger.
5. `docs/roadmap.md` ghi Giai đoạn 1 chỉ phụ thuộc D; A và B chặn Giai đoạn 2/3; C chặn Giai đoạn 2.
6. App thử nghiệm A (app, widget, App Group dạng `<TeamID>.os-widget`, panel không kích hoạt cho C) đã cài và có ghi ngày bắt đầu.

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Chuẩn bị công cụ và tài khoản](./phase-01-chuan-bi-cong-cu-va-tai-khoan.md) | In progress (chờ Apple ID / Team ID trong Xcode) |
| 2 | [Repo và schema Supabase](./phase-02-repo-va-schema-supabase.md) | Completed |
| 3 | [App thử nghiệm A (kèm panel C)](./phase-03-app-thu-nghiem-a.md) | Pending |
| 4 | [Khung Rust và deploy](./phase-04-khung-rust-va-deploy.md) | Pending |
| 5 | [Đo D và quyết định](./phase-05-do-d-va-quyet-dinh.md) | Pending |
| 6 | [Cập nhật tài liệu](./phase-06-cap-nhat-tai-lieu.md) | Pending |

Thứ tự: 1 → 2 → 3 và 4 (độc lập, nên làm 3 trước để đồng hồ 7 ngày chạy sớm) → 5 → 6. Phase 6 cần kết quả của cả 3 và 5.

## Out of scope

Token và RLS hoàn chỉnh (chỉ có một token tạm), dedupe, thông báo lỗi validate, cron dọn dữ liệu, Realtime publication, Hyperdrive, thử nghiệm B, chất lượng mã của app A. Đây là việc của Giai đoạn 1 trở đi.

## Constraints

- Chỉ dùng gói miễn phí của Cloudflare, Supabase và Apple.
- Giữ nguyên API và schema trong `docs/architecture.md` §4.
- Worker gọi Supabase bằng `worker::Fetch`; không dùng `reqwest` hay `postgrest-rs`.
- Đo trên bản deploy, không đo trên `wrangler dev`.
- Không commit secret: khoá service role, token, `.dev.vars`.

## Stop and ask only if

- Thiếu tài khoản Cloudflare, Supabase, Apple ID hoặc khoá service role.
- Kết quả đo không giải thích được (CPU biến động mạnh giữa các lần chạy).
- Chuyển sang TypeScript đòi đổi API hoặc schema.

## Sau plan này

- Ngày 8 kể từ ngày cài app A: kiểm tra A và C, ghi kết quả vào `reports/a-c-results.md` và `docs/architecture.md`.
- Trước Giai đoạn 2: đo B bằng app A ở chế độ agent, chốt NFR-2.
- Giai đoạn 1 tiếp tục trên khung của Phase 4 (hoặc Worker TypeScript nếu D trượt).

<!-- slug: m0-kiem-chung-worker-rust -->
