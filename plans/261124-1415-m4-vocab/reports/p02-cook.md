# Phase 2 cook: schema `vocab_words`, `settings` và hàm gửi từ

Session `m4-vocab-p02-cook`, ngày 2026-11-24. Nhánh `vocab-schema` (worktree `/Users/onedayin20902/personal/os-widget-wt/vocab-schema`), tách từ `main` tại `641deb2`. Chưa merge.

## Kết quả

Migration `supabase/migrations/20261124000000_vocab.sql` tạo hai bảng, giá trị mặc định của `settings`, hàm `vocab_upsert(p_origin text, p_words jsonb) returns integer` và `vocab_tick() returns jsonb` đúng chữ ký Phase 4 gọi. `supabase/tests/vocab_tick.test.sql` có 69 test pgTAP, pass trên Supabase cục bộ sau `supabase db reset` từ đầu.

| Commit | Nội dung |
|---|---|
| `199ac65` | Migration: bảng, mặc định, hai hàm, quyền |
| `b728037` | Test pgTAP |

## Kiểm chứng

- `supabase db reset --local`: áp dụng ba migration không lỗi (hai migration cũ không đổi).
- `supabase test db`: `Files=1, Tests=69, Result: PASS`, chạy ba lần liên tiếp đều pass (test chọn ngẫu nhiên không flaky; phần quay vòng lặp 30 lần).
- `cargo test --workspace`: 187 passed, 0 failed (không đổi Rust).
- `git grep -n "vocab_tick\|vocab_upsert" supabase/`: chỉ hai file của phase này.
- Quét secret theo plan: không có kết quả.

Mỗi hành vi brief yêu cầu đều có test: bảng rỗng (`empty`, không có mục); lần gửi đầu (`sent`, đúng một mục `vocab` với `priority` `normal`, `ttl` 86400 giây, `body` bằng `entry`, `title`, `summary`, `dedupe_key`, đúng một sự kiện `item.created`, `sent_at` và `vocab_last_sent_at` đã ghi); gọi lại ngay (`not_due`); lùi 30 phút (`not_due`) và 59 phút (`sent`); đổi chu kỳ thành 10 (8 phút `not_due`, 10 phút `sent`); hết từ với `stop` (`exhausted`, không có mục, `sent_at` giữ nguyên); hết từ với `rotate` và ba từ (30 lần: luôn `sent`, `rotated = true`, không lần nào là từ gửi gần nhất); `disabled`; chu kỳ 0 dùng 60 kèm cảnh báo; `priority`, `ttl`, `vocab_enabled`, `vocab_last_sent_at`, `vocab_when_exhausted` sai kiểu đều quay về mặc định và có tên trong `warnings`; `vocab_upsert` ghi đè `entry` và `origin`, giữ `added_at`, `sent_at` và `context` cũ khi bản mới không có hoặc rỗng; quyền của `anon` và `authenticated` bị thu hồi trên hai bảng và hai hàm (kiểm bằng `has_*_privilege` và gọi thật bị `42501`); `service_role` chạy trọn một lần `vocab_tick`.

## Thời gian `vocab_tick` trên DB cục bộ (1 000 từ)

Đo bằng `EXPLAIN ANALYZE` và `\timing` của psql trên Postgres 17 cục bộ (Docker trên macOS):

| Trường hợp | Thời gian |
|---|---|
| `sent`, lần gọi đầu của phiên (plan chưa cache) | 2,3 ms |
| `sent`, các lần sau | 0,6–0,9 ms |
| `not_due` | khoảng 0,35 ms |
| `rotate` trên 1 000 từ đã gửi hết (xoá `sent_at` cả bảng rồi chọn) | 6,3 ms |

Đây là thời gian trong Postgres, không tính vào CPU của Worker: Worker chỉ chờ một request PostgREST. Câu hỏi CPU của Phase 7 vẫn là CPU khởi động isolate Rust và dựng request, không phải thời gian SQL.

## Khác với phase file và lý do

1. **`for update` thay vì `for update skip locked`.** Khoá advisory đã tuần tự hoá các lần chạy. Với `skip locked`, một lần nạp đang giữ khoá dòng của từ chưa gửi làm hàm tưởng "hết từ" và quay vòng nhầm. Chờ khoá dòng chỉ kéo dài trong một lệnh upsert ngắn.
2. **Thêm trạng thái `duplicate`.** `dedupe_key` theo phút nên khi bảng chỉ có một từ và `rotate` với chu kỳ 1 phút, hai lần chạy trong cùng phút đụng `dedupe_key`. Hàm dùng `on conflict (dedupe_key) do nothing` và trả `{"status":"duplicate"}` thay vì lỗi, không đổi trạng thái. Phase 4 chỉ ghi `status` ra log nên không phải đổi.
3. **Mọi kết quả đều có `warnings`**, không chỉ `sent`, để cấu hình sai hiện ra cả khi lần chạy là `not_due` hay `disabled`. Trường thêm không ảnh hưởng Phase 4.
4. **Chi tiết không ghi trong phase file:** khoá `settings` bị thiếu thì dùng mặc định không cảnh báo; chu kỳ hợp lệ 1 đến 5 256 000 phút (10 năm) và `ttl` 1 đến 31 536 000 giây (1 năm), ngoài khoảng là giá trị sai; `priority` hợp lệ là `low`, `normal`, `high` như enum `Priority` của crate `envelope`; `vocab_last_sent_at` không đọc được thì coi như chưa gửi lần nào; trong một lô `vocab_upsert` từ lặp lại thì phần tử cuối thắng và chỉ đếm một lần; `p_words` không phải mảng JSON thì báo lỗi `22023`.
5. **`summary`** cắt định nghĩa đầu tiên còn 140 ký tự bằng `left()`, không thêm dấu "…", đúng chữ của phase file.

## Môi trường

- Stack Supabase cục bộ của repo **không chạy** trước khi bắt đầu (chỉ có container `mercury` không liên quan). Tôi chạy `supabase db start` (chỉ container DB) từ worktree; volume DB cũ của repo được khôi phục rồi `db reset`. Đã `supabase stop` khi xong.
- `supabase test db` tải image `public.ecr.aws/supabase/pg_prove:3.36` về Docker (lần đầu bị `toomanyrequests` rồi tự thử lại thành công). Không xoá hay sửa container, image, volume nào khác.
- Không chạy lệnh nào trỏ tới project Supabase thật, không `link`, không `push`.

## Câu hỏi còn mở

Không có.
