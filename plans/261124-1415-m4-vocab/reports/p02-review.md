# Phase 2 review: schema `vocab_words`, `settings` và hàm gửi từ

Session `m4-vocab-p02-review`, ngày 2026-11-24. Nhánh `vocab-schema` (head `a8fa9c7`) đã review, merge vào `main` bằng `--no-ff` ở commit `4cc7ee8`, worktree và nhánh đã xoá.

## Kết luận

Không có finding nào cần sửa, nên không có commit sửa trên nhánh. Migration an toàn để đẩy lên project live ở Phase 7, `vocab_tick` đúng thiết kế và test là test thật (mutation bị bắt).

## Đã kiểm

- **An toàn khi đẩy lên live.** Migration chỉ thêm: hai bảng mới, một chỉ mục, sáu dòng `settings` bằng `on conflict (key) do nothing`, hai hàm mới. Không sửa bảng, chính sách hay hàm có sẵn. Quyền theo mẫu của `20261123000000_access_realtime_cleanup.sql`: `revoke all` trên hai bảng cho `anon` và `authenticated`, bật RLS không chính sách; `revoke execute` hai hàm khỏi `public, anon, authenticated`, `grant execute` cho `service_role`. Hai hàm là `security invoker` (đúng phase file; brief nhắc `security definer`, nhưng điều kiện chính là ghim `search_path`, và cả hai đều `set search_path = ''`, tham chiếu bảng bằng `public.`). Đường dự phòng `pg_cron` ở Phase 7 chạy bằng `postgres` nên invoker vẫn đủ quyền.
- **Một lần chạy, không gửi trùng.** Khoá `pg_advisory_xact_lock` lấy trước khi đọc `settings`; ở READ COMMITTED mỗi câu lệnh có snapshot mới, nên lần chạy chồng nhau đợi xong rồi thấy `vocab_last_sent_at` mới và trả `not_due`. Mỗi lần gọi chèn tối đa một dòng `items`; va `dedupe_key` thì trả `duplicate`, không lỗi.
- **Quay vòng không gửi lại từ vừa gửi.** `last_word` là từ có `sent_at` lớn nhất trước khi xoá `sent_at`; lần chọn sau loại từ này khi bảng có hơn một từ.
- **Mục chèn khớp client.** `body = entry` là `VocabBody` đã kiểm bằng `envelope::check_vocab` (`word`, `ipa`, `pos`, ít nhất một `definition` không rỗng), nên `title` và `summary` không null (cột `not null` của `items`), và `VocabContent.init?(json:)` giải mã được. `priority` và `expires_at` lấy từ `settings`, có test riêng (`high`, 600 giây).
- **`vocab_upsert`.** Khi Worker tuần tự lại `VocabBody` có `context: null`, `->> 'context'` là null nên `context` cũ được giữ, đúng quyết định nạp lại.
- **Test tất định.** Phần chọn ngẫu nhiên lặp 30 lần với ba từ; nếu điều kiện loại từ vừa gửi bị bỏ, xác suất test vẫn pass là (2/3)^30, khoảng 5·10⁻⁶.

## Mutation

Thay `and (word_count = 1 or w.word <> last_word)` bằng `and true` trong lần chọn sau quay vòng: `supabase test db` báo `Failed test 27: "a rotation never resends the word sent last"`, 1/69 fail. Đã revert bằng `git checkout`, nhánh sạch.

## Merge và kiểm sau merge trên `main`

| Bước | Kết quả |
|---|---|
| Merge `main` vào nhánh | Không cần: `main` chỉ thêm file widget và plan, `git merge-tree` sạch |
| `git merge --no-ff vocab-schema` | `4cc7ee8` |
| `cargo test --workspace` | 187 passed, 0 failed |
| `swift test` (OSWidgetKit) | 188 tests, 19 suites, passed |
| `supabase db reset --local` từ `main` | Áp dụng ba migration không lỗi |
| `supabase test db` | 69 tests, PASS |

## Môi trường

Chỉ dùng stack cục bộ (`supabase db start`, `db reset --local`, `test db`), rồi `supabase stop`; chỉ còn container `mercury` không liên quan. Không `link`, `push` hay `--db-url`. Không xoá image hay container nào khác.

## Câu hỏi còn mở

Không có.
