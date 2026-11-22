---
phase: 2
title: "Repo và schema Supabase"
status: pending
priority: P1
effort: "1h"
dependencies: [1]
---

# Phase 2: Repo và schema Supabase

## Goal

Đưa thư mục thành repo git có `.gitignore` chặn secret, và tạo bảng `items`, `events` cùng trigger ghi sự kiện trên Supabase đúng theo `docs/architecture.md` §4.3.

## Files to Create / Modify

- Create: `.gitignore`
- Create: `supabase/config.toml` (do `supabase init` sinh)
- Create: `supabase/migrations/20261122000000_items_events.sql`

## Tasks & Steps

- [ ] `git init` ở gốc `os-widget`.
- [ ] Tạo `.gitignore` chặn ít nhất: `target/`, `build/`, `node_modules/`, `.wrangler/`, `.dev.vars`, `.env*`, `*.xcodeproj/xcuserdata/`, `DerivedData/`, `.DS_Store`, `supabase/.temp/`.
- [ ] `supabase init`, sau đó `supabase link --project-ref <ref>`.
- [ ] Viết migration với đúng cột của `items` và `events` như §4.3 (không thêm, không bớt cột).
- [ ] Viết hàm trigger `record_item_event()` chạy `after insert or update on items for each row`:
  - Insert: ghi `item.created`.
  - `read_at` từ null sang có giá trị: ghi `item.read`; từ có giá trị sang null: ghi `item.unread`.
  - `deleted_at` từ null sang có giá trị: ghi `item.deleted`.
- [ ] Bật RLS trên cả hai bảng và không tạo policy nào. Service role vẫn ghi đọc được; quyền đọc `events` cho khoá anon là việc của Giai đoạn 1.
- [ ] `supabase db push`.

## Verification

- `git status` chạy được và không liệt kê file secret nào.
- Chạy bằng `psql` với chuỗi kết nối của project (không lưu chuỗi này vào repo): insert một dòng `items`, update `read_at`, rồi update `deleted_at`. `select type from events order by seq` trả về đúng `item.created`, `item.read`, `item.deleted`. Xoá dữ liệu thử sau khi kiểm.

## Risk Assessment

- `supabase db push` lỗi vì chưa link hoặc sai mật khẩu DB: chạy lại `supabase link`; không chỉnh schema để lách lỗi.
