---
title: "M1: Server"
description: "Hoàn thành Giai đoạn 1 của roadmap: schema và RLS đầy đủ, envelope ba loại, Worker năm endpoint với hai token, CLI publish và tác vụ dọn dữ liệu, kiểm chứng trên bản deploy."
status: pending
priority: P1
effort: 14h
branch: main
tags: [feature, backend, database, api, auth]
blockedBy: []
blocks: []
created: 2026-11-23
---

# M1: Server

## Overview

Hoàn thành Giai đoạn 1 của [roadmap](../../docs/roadmap.md#giai-đoạn-1-server) trên khung Rust của M0 ([plan M0](../261122-0754-m0-kiem-chung-worker-rust/plan.md)). Kết thúc plan này, bên gửi publish được mục qua CLI, client đọc được mục qua API thật, và sáu tiêu chí hoàn thành của Giai đoạn 1 được kiểm trên bản deploy bằng một script lặp lại được.

Thiết kế theo [architecture.md](../../docs/architecture.md) §3, §4, §5, §7. Những chỗ architecture chưa nói rõ được chốt trong các phase và ghi lại vào architecture ở Phase 5.

## Done means

Sáu tiêu chí của roadmap Giai đoạn 1, kiểm bằng `scripts/acceptance-server.sh` trên Worker đã deploy:

1. CLI publish một mục và `GET /events` trả về mục đó.
2. Envelope sai định dạng bị từ chối với thông báo nêu rõ trường sai.
3. Publish hai lần cùng `dedupe_key` chỉ tạo một mục.
4. Đánh dấu đã đọc và xoá sinh đúng sự kiện.
5. Request thiếu token hoặc dùng sai loại token bị từ chối.
6. Khoá anon đọc được `events` nhưng không đọc được `items`.

Thêm: `GET /events` có `limit` (mặc định 100, tối đa 100); tác vụ dọn dữ liệu đã lên lịch trên Supabase; `SPIKE_TOKEN` đã bị gỡ; architecture và roadmap ghi đúng những gì đã làm.

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Schema, RLS và tác vụ dọn trên Supabase](./phase-01-schema-supabase.md) | Pending |
| 2 | [Envelope ba loại và lỗi nêu rõ trường](./phase-02-envelope-ba-loai.md) | Pending |
| 3 | [Worker năm endpoint, hai token](./phase-03-worker-api-hai-token.md) | Pending |
| 4 | [CLI publish](./phase-04-cli-publish.md) | Pending |
| 5 | [Deploy, nghiệm thu và cập nhật tài liệu](./phase-05-deploy-va-nghiem-thu.md) | Pending |

Thứ tự: Phase 1 và 2 độc lập, làm song song được. Phase 3 cần cả 1 và 2. Phase 4 cần 2 (kiểm thật với server cần 3). Phase 5 cần tất cả.

## Scope Challenge

- Có sẵn: crate `envelope` (chỉ `notification`), Worker `POST /items` và `GET /events` với một token tạm, migration bảng và trigger, script đo CPU.
- Phạm vi: đúng năm gạch đầu dòng và sáu tiêu chí của roadmap Giai đoạn 1. Giữ nguyên phạm vi (HOLD).
- Độ phức tạp: 5 phase vì mỗi phase là một lớp riêng (DB, crate định dạng, Worker, CLI, deploy); khoảng 12 file, một crate mới (`cli`).

## Out of scope

Realtime ở phía client, bảng `vocab_words` và `settings`, endpoint `POST /vocab/words`, Cron Trigger từ vựng (Giai đoạn 4); mọi mã Swift (Giai đoạn 2); Hyperdrive; đo lại CPU.

## Constraints

- Chỉ gói miễn phí của Cloudflare và Supabase.
- Worker gọi Supabase qua PostgREST bằng `worker::Fetch`; không dùng `reqwest` hay `postgrest-rs` trong Worker.
- Crate `envelope` phải build được cho cả `wasm32-unknown-unknown` và máy thật.
- Giữ định dạng JSON ở architecture §3; test round-trip hiện có phải còn pass.
- Không commit secret. Kiểm bằng `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'`.
- Lệnh `--linked` của Supabase chạy `supabase link --project-ref gykrhmpliphrcpiryzuq` trước (main worktree chưa link).

## Stop and ask only if

- Thiếu quyền Cloudflare hoặc Supabase, hoặc thiếu khoá service role.
- `pg_cron` không bật được trên project.
- Cloudflare bắt đầu chặn request vì vượt CPU.
- Một tiêu chí chỉ đạt được nếu đổi API hoặc schema ở architecture §4 theo cách chưa nêu trong plan này.

## Validation Log

### Session 1 (2026-11-23)

| Câu hỏi | Quyết định | Phase bị ảnh hưởng |
|---|---|---|
| `ttl` mặc định khi bên gửi không đặt | 7 ngày (thay cho 30 ngày tạm đặt) | 3, 5 |
| Tác vụ dọn chạy ở đâu | `pg_cron` ở Supabase | 1 |
| Trường bắt buộc của `vocab` | `word`, `ipa`, `pos`, `meanings` | 2 |
| Realtime publication cho `events` | Làm luôn ở M1 | 1 |

Whole-plan sweep: `ak plan validate` hợp lệ; `ttl` 7 ngày đã truyền vào Phase 3 (hằng số), Phase 5 (kiểm `expires_at`, architecture §3.1, roadmap, PRD); Phase 1 nêu thời gian giữ 30 ngày độc lập với `ttl`. Không còn chỗ nào trong plan nói `ttl` mặc định 30 ngày.

<!-- slug: m1-server -->
