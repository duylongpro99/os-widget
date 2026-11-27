# Review Phase 7: deploy, đo CPU cron và nghiệm thu server

Session `m4-vocab-p07-review`, ngày 2026-11-27 (Asia/Saigon). Phạm vi: nhánh `vocab-acceptance` (đầu nhánh lúc nhận `a5f891f`) so với `main` (`e30d215`). Nhánh chỉ thêm `scripts/acceptance-vocab.sh` và `reports/acceptance-server.md`. Không chạy script trên live, không gọi live.

## Kết luận

Nhánh đạt, sau một sửa nhỏ ở script. Báo cáo nghiệm thu khớp đầu ra script mà nó trích, các phép tính CPU đúng, và không có secret. Mọi todo của Phase 7 đã được báo cáo chứng minh, trừ đường dự phòng G5. G5 không cần, vì không lần chạy nào `exceededCpu`.

## Phát hiện

| # | Mức | Vị trí | Mô tả | Xử lý |
|---|---|---|---|---|
| 1 | Nhỏ | `scripts/acceptance-vocab.sh`, hàm `decode` | Hàm giải mã URI kiểu form: đổi `+` thành dấu cách, và `printf '%b'` đọc dấu `\` có sẵn như ký tự escape. Mật khẩu DB có `+` hoặc `\` sẽ bị đổi, và `psql` không đăng nhập được. Theo RFC 3986 và libpq, phần userinfo chỉ giải mã `%XX`. Đã kiểm: `a+b%2Bc\tz` trước khi sửa cho `a b+c<tab>z`, sau khi sửa cho `a+b+c\tz`, trên cả bash 3.2 và bash mới. Lần chạy live không bị ảnh hưởng, vì mật khẩu hiện tại đã đăng nhập được. | Sửa ở `13cb6cc` |
| 2 | Ghi chú | `scripts/acceptance-vocab.sh`, dòng dựng `pg_env` | `PGSSLMODE=require` cố định, và tham số `?sslmode=…` trong URI bị bỏ qua. Đúng với Supabase, nên không sửa. | Không sửa |
| 3 | Ghi chú | Đầu ra tiêu chí 5 | Các ghi chú nối bằng `;` không có dấu cách (`Result: PASS;live …`). Chỉ là trình bày; báo cáo trích đúng nguyên văn. | Không sửa |

## Đã kiểm trên script

- `bash -n` và `shellcheck` sạch, trước và sau khi sửa.
- Hai lần chờ của tiêu chí 4 dùng `wait_for` theo `date +%s` với bước `sleep 10`, nên máy ngủ không kéo dài thời gian `settings` bị đổi.
- Trap `EXIT`: `restore_sql` được đặt trước lần `update` đầu tiên. Nếu `latest_seq` hay `sql` lỗi giữa chừng, `set -e` thoát và trap trả lại `vocab_interval_minutes`. Khi trả lại thành công, script xoá `restore_sql`; khi thất bại, trap thử lại và in câu SQL cần chạy (không chứa secret). Stack Supabase cục bộ chỉ bị dừng khi chính script đã bật.
- Không in secret: token đi qua file header mode 600 trong thư mục tạm mode 700; mật khẩu vào `psql` qua biến `PG*`, không nằm trên dòng lệnh. Không thông báo lỗi nào in `SUPABASE_DB_URL`.
- `GET /items` trả `seq` (`crates/worker/src/items.rs`), và `GET /events` mặc định trang 100 (`crates/worker/src/events.rs`), khớp cách phân trang của `events_since`.
- `vocab-cron` là `source` do `vocab_tick` ghi (`supabase/migrations/20261124000000_vocab.sql`), và log `vocab.tick status=…` có trong `crates/worker/src/vocab.rs`.

## Đã kiểm trên báo cáo nghiệm thu

- Số CPU cron `empty`: 13 giá trị cho p50 9 ms (nearest-rank), lớn nhất 17 ms, trung bình 9,3 ms, 4 lần vượt 10 ms; `wallTime` p50 859 ms, lớn nhất 1194 ms. `POST /vocab/words`: p50 7 ms, lớn nhất 28 ms, 3/6 vượt 10 ms. Đều đúng.
- Tiêu chí 4: 21:40:31 trừ 21:25:32 là 899 giây; 131 thẻ từ 22:05:32 đến 08:55:31 là 130 khoảng 5 phút. Hai lần cạn bộ 62 từ lúc 03:10 và 08:20 khớp 62 × 5 phút.
- Số từ cuối: 13 + 45 + 3 + 1 = 62.
- Mã Worker và migration không đổi giữa `b44cd2f` (commit đã deploy) và `main`.
- Các đường dẫn trích dẫn có trong repo: `reports/api-coverage.md`, `crates/cli/tests/fixtures/book/sample.txt`, `scripts/acceptance-server.sh`, migration vocab, file phase 5 của M1.
- Quét khoá `sb_secret_`, JWT, chuỗi kết nối Postgres và `Bearer` kèm token dài trên diff (mẫu ở mục Verification của Phase 7): không có kết quả.

## Trạng thái phase

Phase 7 đã đánh dấu Completed trong file phase và `plan.md` (`bd6073f`). Mỗi todo đã tick có trỏ tới mục bằng chứng trong `reports/acceptance-server.md`. Todo G5 để trống với lý do: không cần, vì không lần chạy nào `exceededCpu`. Số CPU cho `docs/architecture.md` §8 thuộc Phase 10; review này không sửa `docs/`.
