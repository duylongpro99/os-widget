---
title: "Lập plan M1: Server"
date: 2026-11-23
summary: "Tạo plan 5 phase cho Giai đoạn 1: schema và RLS, envelope ba loại, Worker hai token, CLI publish, deploy và nghiệm thu"
---

# Lập plan M1: Server

## What happened
Tạo plan `plans/261123-0159-m1-server` (5 phase, `ak plan validate` OK) cho Giai đoạn 1 của `docs/roadmap.md`, dựng tiếp trên khung Rust của M0.

## Decision
- `ttl` mặc định đổi từ 30 ngày tạm đặt thành 7 ngày (chủ dự án chọn).
- Tác vụ dọn chạy bằng `pg_cron` ở Supabase; thời gian giữ sự kiện và mục đã xoá là 30 ngày.
- `vocab` bắt buộc `word`, `ipa`, `pos`, `meanings`.
- `events` vào publication Realtime ngay ở M1.
- Lỗi validate nêu đường dẫn trường nhờ parse hai bước với `serde_path_to_error`, vì `serde(flatten)` làm mất đường dẫn bên trong `body`.
- Chống trùng bằng `on_conflict=dedupe_key` với `ignore-duplicates` rồi đọc lại id, không cần hàm SQL.
- 401 cho token không khớp, 403 cho token sai loại; `PATCH` và `DELETE` idempotent, 404 khi mục không tồn tại hoặc đã xoá.

## Next steps
- `/ak-cook plans/261123-0159-m1-server/plan.md`; Phase 1 và 2 làm song song được.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
