---
phase: 1
title: "Schema, RLS và tác vụ dọn trên Supabase"
status: completed
priority: P1
effort: "3h"
dependencies: []
---

# Phase 1: Schema, RLS và tác vụ dọn trên Supabase

## Goal

Thêm một migration mới để khoá anon chỉ đọc được `events`, `events` nằm trong publication Realtime, và một tác vụ `pg_cron` dọn mục hết hạn, mục đã xoá và sự kiện cũ. Migration M0 (`20261122000000_items_events.sql`) đã chạy trên project và giữ nguyên.

## Files to Create / Modify

- Create: `supabase/migrations/20261123000000_access_realtime_cleanup.sql`

## Thiết kế đã chốt

**Quyền truy cập.** Supabase mặc định cấp quyền bảng trong `public` cho `anon` và `authenticated`; RLS không có policy chỉ trả về rỗng. Phase này đóng cả hai lớp:

- `items`: `revoke all on items from anon, authenticated`. Không policy nào.
- `events`: `revoke all on events from anon, authenticated`, rồi `grant select on events to anon` và một policy `for select to anon using (true)`. Không cấp gì cho `authenticated` (app không đăng nhập).

**Realtime.** `alter publication supabase_realtime add table events;` (architecture §4.3). Client chỉ dùng tín hiệu này từ Giai đoạn 2; đặt ở đây vì nó thuộc schema server.

**Tác vụ dọn.** Một hàm SQL `purge_old_rows()` (`security definer`, `set search_path = ''`) làm ba việc trong một lần gọi:

1. Xoá hẳn mục đã hết hạn: `expires_at < now()`. Client tự ẩn mục hết hạn, nên không cần thời gian chờ.
2. Xoá hẳn mục đã xoá mềm quá thời gian giữ: `deleted_at < now() - interval '30 days'`.
3. Xoá sự kiện quá thời gian giữ: `created_at < now() - interval '30 days'`.

Thời gian giữ 30 ngày dài hơn `ttl` mặc định 7 ngày và áp dụng độc lập với nó. Thời gian giữ cho mục đã xoá bằng thời gian giữ sự kiện, để máy nào bắt kịp trong vòng 30 ngày vẫn thấy sự kiện `item.deleted` trước khi mục biến mất hẳn. Máy ngoại tuyến lâu hơn thế dựa vào đối chiếu định kỳ với `GET /items` (architecture §5); sự kiện `item.created` có mục đã bị xoá hẳn được Worker trả về với `item: null` và client bỏ qua.

Lên lịch bằng `pg_cron` mỗi ngày một lần: `create extension if not exists pg_cron with schema pg_catalog;` rồi `select cron.schedule('os-widget-purge', '17 3 * * *', 'select public.purge_old_rows()');`. Chọn `pg_cron` thay vì Cron Trigger của Worker vì việc này thuần SQL, không tốn CPU Worker, không chiếm một trong 5 Cron Trigger miễn phí, và nằm trọn trong migration.

**Hàm không lộ qua PostgREST.** Postgres cấp `execute` cho `public` mặc định, nên PostgREST sẽ mở `rpc/purge_old_rows` cho anon. Migration chạy `revoke execute on function public.purge_old_rows() from public, anon, authenticated;`.

## Tasks & Steps

- [x] Viết migration theo thiết kế trên, comment giải thích lý do của từng khối (quyền hai lớp, thời gian giữ, revoke execute).
- [x] Chạy cục bộ: `supabase start` rồi `supabase db reset` (Docker đã có). Migration áp dụng không lỗi.
- [x] Kiểm cục bộ bằng `psql` vào DB local:
  - Với vai trò `anon` (`set role anon`): `select * from events` chạy được; `select * from items` lỗi quyền; `select public.purge_old_rows()` lỗi quyền.
  - Với `postgres`: chèn một mục có `expires_at` trong quá khứ, một mục có `deleted_at` cách đây 31 ngày, một mục có `deleted_at` hôm nay, một sự kiện có `created_at` cách đây 31 ngày (sửa `created_at` sau khi trigger ghi); gọi `select public.purge_old_rows()`; chỉ mục xoá hôm nay và các sự kiện mới còn lại.
  - `select jobname, schedule from cron.job` có `os-widget-purge`.
  - `select tablename from pg_publication_tables where pubname = 'supabase_realtime'` có `events`.
- [x] Đẩy lên project: `supabase link --project-ref gykrhmpliphrcpiryzuq` rồi `supabase db push`. Lặp lại kiểm tra `cron.job` và publication trên project qua `psql` với chuỗi kết nối của project (không lưu chuỗi này vào repo).
- [x] `supabase stop` sau khi kiểm xong cục bộ.

## Verification

- `supabase db reset` không lỗi.
- Các truy vấn kiểm ở trên cho đúng kết quả cả cục bộ và trên project.
- Tiêu chí 6 kiểm lại qua HTTP bằng khoá anon ở Phase 5.

## Risk Assessment

- `pg_cron` cần bật trong dashboard trước khi `create extension` chạy được: nếu `db push` lỗi vì extension, bật `pg_cron` trong Database → Extensions rồi đẩy lại; không bỏ phần lên lịch.
- `alter publication` lỗi vì bảng đã có trong publication: dùng khối `do $$ ... $$` kiểm `pg_publication_tables` trước khi thêm.
- Supabase đã chuyển sang khoá "publishable" thay cho khoá anon kiểu cũ; cả hai đều chạy dưới vai trò `anon`, nên quyền ở đây áp dụng cho cả hai.

## Rollback

Migration mới chỉ thêm quyền, policy, publication, hàm và job. Gỡ bằng một migration ngược: `cron.unschedule('os-widget-purge')`, `drop function purge_old_rows`, bỏ `events` khỏi publication, drop policy.
