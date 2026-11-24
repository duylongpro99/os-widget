---
phase: 2
title: "Schema vocab_words, settings và hàm gửi từ"
status: completed
priority: P1
effort: "4h"
dependencies: []
---

# Phase 2: Schema `vocab_words`, `settings` và hàm gửi từ

Server-only. Không chạm `apps/`.

## Goal

Một migration tạo bảng `vocab_words` và `settings` với giá trị mặc định, hàm `vocab_upsert` cho endpoint nạp từ và hàm `vocab_tick` làm toàn bộ việc của một lần chạy cron trong một lệnh SQL, kiểm bằng test pgTAP trên Supabase cục bộ.

## Context

- Architecture §4.4: bảng `vocab_words(word pk, entry jsonb, origin, added_at, sent_at)` và `settings(key pk, value jsonb)`; cron so thời điểm gửi gần nhất với `vocab_interval_minutes`; khi hết từ làm theo `vocab_when_exhausted`.
- Cron Trigger ở gói miễn phí có 10 ms CPU mỗi lần chạy và isolate Rust lạnh đã tốn 16–21 ms (architecture §8). Vì vậy Worker chỉ gọi một RPC; mọi lựa chọn nằm trong SQL.
- Bảng `items` và trigger `items_record_event` ở `supabase/migrations/20261122000000_items_events.sql`: chèn một dòng vào `items` tự sinh `item.created`.
- Quyền theo mẫu của `supabase/migrations/20261123000000_access_realtime_cleanup.sql`: thu hồi quyền của `anon` và `authenticated`, bật RLS không chính sách, thu hồi `execute` mặc định của hàm.

## Files to Create / Modify

- Create: `supabase/migrations/20261124000000_vocab.sql`
- Create: `supabase/tests/vocab_tick.test.sql` (pgTAP, chạy bằng `supabase test db`)

## Thiết kế

**Bảng.** Đúng architecture §4.4; thêm `check (word = lower(btrim(word)) and word <> '')` cho `vocab_words.word` và chỉ mục `vocab_words (sent_at)`. `revoke all ... from anon, authenticated` và `enable row level security` cho cả hai bảng.

**Giá trị mặc định trong `settings`** (`insert ... on conflict (key) do nothing`, nên chạy lại migration không ghi đè cấu hình đã sửa):

| Khoá | Giá trị mặc định | Ý nghĩa |
|---|---|---|
| `vocab_enabled` | `true` | `false` thì `vocab_tick` không làm gì; dùng để tắt nhanh không cần deploy. |
| `vocab_interval_minutes` | `60` | Chu kỳ gửi. |
| `vocab_when_exhausted` | `"rotate"` (câu hỏi 1) | `"stop"` hoặc `"rotate"`. |
| `vocab_priority` | `"normal"` (câu hỏi 3) | `priority` của mục gửi đi. |
| `vocab_item_ttl_seconds` | `86400` (câu hỏi 4) | `expires_at = now() + ttl`. |
| `vocab_last_sent_at` | `null` | Trạng thái do `vocab_tick` ghi. |

Giá trị sai kiểu hoặc ngoài phạm vi (chu kỳ < 1, ttl < 1, `when_exhausted` hay `priority` lạ) bị thay bằng giá trị mặc định và tên khoá được đưa vào trường `warnings` của kết quả, không làm hàm lỗi.

**`vocab_upsert(p_origin text, p_words jsonb) returns integer`.** `p_words` là mảng body `vocab` đã được Worker kiểm. Với mỗi phần tử: khoá là `lower(btrim(entry->>'word'))`; `insert ... on conflict (word) do update set entry = <mới>, origin = excluded.origin`, giữ `added_at` và `sent_at`; nếu `entry` mới không có `context` (hoặc rỗng) mà bản cũ có thì giữ `context` cũ (câu hỏi 7). Trả số từ đã ghi.

**`vocab_tick() returns jsonb`.** Trong một transaction:

1. `pg_advisory_xact_lock(hashtext('os-widget.vocab_tick'))`: lần chạy chồng nhau đợi nhau.
2. Đọc `settings`. `vocab_enabled = false` → trả `{"status":"disabled"}`.
3. Nếu `vocab_last_sent_at` khác null và `now() < vocab_last_sent_at + make_interval(mins => interval) - interval '1 minute'` → `{"status":"not_due"}`.
4. Chọn một từ `sent_at is null` theo thứ tự ngẫu nhiên (câu hỏi 6), `for update skip locked`.
5. Không còn từ chưa gửi: bảng rỗng → `{"status":"empty"}`; `"stop"` → `{"status":"exhausted"}`; `"rotate"` → `update vocab_words set sent_at = null`, rồi chọn lại, loại từ có `sent_at` lớn nhất trước khi xoá nếu bảng có hơn một từ. Không bao giờ tạo mục khi không có từ (FR-27).
6. Chèn vào `items`: `id = gen_random_uuid()::text`, `kind = 'vocab'`, `source = 'vocab-cron'`, `priority` từ settings, `title = entry->>'word'`, `summary = '(' || pos || ') ' || ` định nghĩa đầu tiên cắt còn tối đa 140 ký tự, `body = entry`, `dedupe_key = 'vocab:' || word || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDD"T"HH24MI')`, `expires_at = now() + ttl`.
7. `update vocab_words set sent_at = now()`; ghi `vocab_last_sent_at = now()`.
8. Trả `{"status":"sent","word":..., "item_id":..., "rotated":bool, "warnings":[...]}`.

`title` không chứa xuống dòng và `summary` không rỗng vì `entry` đã qua kiểm của crate `envelope` lúc nạp (Phase 3).

**Quyền hàm.** Cả hai hàm `security invoker`, `set search_path = ''`, tham chiếu bảng bằng `public.`; `revoke execute ... from public, anon, authenticated`; `grant execute ... to service_role`.

## Tasks & Steps

- [ ] Viết migration theo thiết kế trên.
- [ ] Viết test pgTAP (mỗi test trong transaction, giả thời gian bằng cách đặt `vocab_last_sent_at` lùi về quá khứ):
  - bảng rỗng → `empty`, không có dòng mới trong `items`;
  - có từ, chưa gửi lần nào → `sent`, đúng một dòng `items` `kind = 'vocab'` với `body` bằng `entry`, một sự kiện `item.created`, `sent_at` đã đặt;
  - gọi lại ngay → `not_due`;
  - `vocab_last_sent_at` lùi 59 phút với chu kỳ 60 → `sent` (bù 1 phút); lùi 30 phút → `not_due`;
  - đổi `vocab_interval_minutes` thành 10 rồi lùi 10 phút → `sent` (tiêu chí 4 ở mức SQL);
  - hết từ với `"stop"` → `exhausted`, không thêm dòng `items`;
  - hết từ với `"rotate"` và ba từ → `sent` với `rotated = true`, từ được gửi khác từ gửi gần nhất;
  - `vocab_enabled = false` → `disabled`;
  - `vocab_interval_minutes = 0` → dùng 60 và có cảnh báo;
  - `vocab_upsert` hai lần cùng từ → một dòng; lần hai không có `context` thì giữ `context` cũ; `sent_at` không đổi;
  - `anon` không gọi được `vocab_tick`, `vocab_upsert` và không đọc được hai bảng.
- [ ] `supabase start`, `supabase db reset`, `supabase test db`, `supabase stop`.

## Verification

- `supabase db reset` áp dụng ba migration không lỗi.
- `supabase test db` pass toàn bộ.
- `git grep -n "vocab_tick\|vocab_upsert" supabase/` chỉ có hai file của phase này.

## Risk Assessment

- `order by random()` quét cả bảng: bộ từ dự kiến vài nghìn dòng, chi phí không đáng kể trong Postgres và không tính vào CPU Worker.
- `pg_advisory_xact_lock` giữ tới hết transaction: hàm ngắn, không có I/O ngoài DB.
- `supabase test db` cần extension pgTAP: Supabase cục bộ có sẵn; nếu thiếu, thêm `create extension if not exists pgtap` ở đầu file test, không thêm vào migration.

## Rollback

Migration chưa đẩy lên project ở phase này. Nếu đã đẩy (Phase 7), rollback bằng một migration mới `drop function vocab_tick(), vocab_upsert(text, jsonb); drop table vocab_words, settings;` sau khi gỡ Cron Trigger.
