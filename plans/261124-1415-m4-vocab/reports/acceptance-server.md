# Nghiệm thu server M4, phần 1: migration, deploy Cron Trigger, đo CPU

Session `m4-vocab-p07-live`, ngày 2026-11-24 (Asia/Saigon). Nhánh `vocab-acceptance`, worktree `/Users/onedayin20902/personal/os-widget-wt/vocab-acceptance`.

## Kết luận

G1 và G2 đạt. Migration `20261124000000_vocab.sql` đã lên project live sau khi sao lưu. Worker chạy Cron Trigger `*/5 * * * *`, và `scripts/acceptance-server.sh` vẫn pass 8/8. Đã ghi được 13 lần chạy cron từ 15:45 đến 17:00: tất cả có `outcome` `ok`, trả `vocab.tick status=empty`, CPU p50 9 ms và lớn nhất 17 ms. Không lần nào `exceededCpu`, nên không cần đường dự phòng `pg_cron` (G5). Tiêu chí 5 PASS. Tiêu chí 2 đến 4 (G3, G4) để lại cho session sau, vì đợt đếm reload 24 giờ của widget đang chạy.

## Môi trường

- Commit deploy: `b44cd2f` (`main`). Nhánh này chỉ thêm script và báo cáo, không đổi mã Worker hay migration.
- Supabase CLI 2.122.0; project `gykrhmpliphrcpiryzuq` (tên `os-widget`), đúng project trong báo cáo M1. CLI bản này đọc `supabase/.temp/project-ref` thay cho `linked-project.json` M1 để lại, nên đã chạy `supabase link --project-ref gykrhmpliphrcpiryzuq` trong worktree (cùng project, chỉ ghi `.temp` đã gitignore).
- wrangler 4.166.0 qua `npx`, cùng phiên bản M0 dùng; đã đăng nhập sẵn.
- Secret của Worker trước deploy: `CLIENT_TOKEN`, `PUBLISH_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY`, đủ như M1, nên không `wrangler secret put`.
- Token, khoá publishable và mật khẩu DB lấy từ macOS Keychain ngay trong lệnh cần; không giá trị nào được in ra hay ghi vào repo.

## G1: sao lưu và migration

Sao lưu lúc 15:31–15:32, bằng `supabase db dump --linked` (schema) và `supabase db dump --linked --data-only` (dữ liệu), vào thư mục `~/Backups/os-widget/` (mode 700), mỗi file mode 600:

| File | Dung lượng | Kiểm |
|---|---|---|
| `before-vocab-20261124-schema.sql` | 6273 byte | Có `CREATE TABLE` cho `items` và `events` |
| `before-vocab-20261124-data.sql` | 23812 byte | Có `INSERT INTO "public"."items"` và `"public"."events"` |

`supabase migration list --linked` trước khi đẩy: `20261122000000` và `20261123000000` đã có trên remote, chỉ `20261124000000` còn thiếu. `supabase db push --dry-run` liệt kê đúng `20261124000000_vocab.sql`. Rồi `supabase db push`:

```text
Applying migration 20261124000000_vocab.sql...
{"upToDate":false,"dryRun":false,"migrations":["20261124000000_vocab.sql"],"seeds":[],"roles":[],"message":"Finished supabase db push."}
```

Sau đó `migration list` cho cả ba migration có ở local và remote.

`select key, value from settings` trên live:

| key | value |
|---|---|
| `vocab_enabled` | `true` |
| `vocab_interval_minutes` | `60` |
| `vocab_item_ttl_seconds` | `86400` |
| `vocab_last_sent_at` | `null` |
| `vocab_priority` | `"normal"` |
| `vocab_when_exhausted` | `"rotate"` |

Đủ sáu khoá, đúng giá trị đã chốt (D5, D7, D8). `vocab_words` có 0 dòng.

Quyền của anon. Với khoá publishable gửi qua PostgREST:

- `GET /rest/v1/vocab_words` trả 401 (`42501 permission denied`).
- `GET /rest/v1/settings` trả 401 (`42501 permission denied`).
- `POST /rest/v1/rpc/vocab_tick` trả 401 (`permission denied for function vocab_tick`).
- `POST /rest/v1/rpc/vocab_upsert` (body `{}`) trả 404 `PGRST202`.

Trong DB, `anon` và `authenticated` không có quyền bảng nào trên hai bảng, và `has_function_privilege('anon', …, 'execute')` là `false` cho cả hai hàm.

## G2: deploy Worker có Cron Trigger

`npx wrangler@4.166.0 deploy` từ `crates/worker`, lúc 15:33:07–15:33:35:

```text
Total Upload: 684.06 KiB / gzip: 224.20 KiB
Worker Startup Time: 7 ms
Uploaded os-widget (2.81 sec)
Deployed os-widget triggers (1.08 sec)
  https://os-widget.longdaobk17.workers.dev
  schedule: */5 * * * *
Current Version ID: bf216bba-294f-4cf2-b412-9171e2d999b1
```

So với bản M1 (656.64 KiB, gzip 216.96 KiB), bản mới tăng khoảng 27 KiB chưa nén. Đây là bản đã qua `wasm-opt`, do `worker-build` tự tải về.

Lần chạy cron đầu tiên tới lúc 15:45:31. Hai mốc 15:35 và 15:40 không chạy, vì trigger mới mất khoảng 10 phút mới có hiệu lực.

### `scripts/acceptance-server.sh` trên bản deploy

Chạy 15:33:55–15:34:19, mã thoát 0:

```text
run acceptance-20261124T153356-46316 against https://os-widget.longdaobk17.workers.dev
starting at seq 447
PASS 1 CLI publish f7958200-4d84-4b79-a0b3-c37ff8db5d76 appears in GET /events as item.created with its item
PASS 2 invalid envelopes: no title -> 400 {"field":"","message":"missing field `title`"}; vocab without definition -> 400 {"field":"body.meanings[0]","message":"missing field `definition`"}; kind weather -> 400 {"field":"kind","message":"unknown kind `weather`, expected one of notification, vocab, generic"}
PASS 3 dedupe: first 201, second 200, same id dd601128-2bd3-49ce-82e7-17f8aa60a630, one item.created
PASS 4 read/unread/delete on 125a34a9-3d42-4b73-bfd1-9379b97aae13: 204 with item.read, item.unread, item.deleted; repeats add no event; PATCH after delete 404
PASS 5 tokens: none -> 401, client token on POST /items -> 403, publish token on GET /events -> 403, wrong token -> 401
PASS 6 anon key: events -> 200 array, items -> 401 no rows, rpc/purge_old_rows -> 401 rejected
PASS limit: since=0&limit=500 -> 200 with 100 events (max 100), limit=0 -> 400
PASS default ttl: expires_at - created_at = 604799s (7 days = 604800s)
checks failed: 0
cleanup: DELETE /items/f7958200-4d84-4b79-a0b3-c37ff8db5d76 -> 204
cleanup: DELETE /items/dd601128-2bd3-49ce-82e7-17f8aa60a630 -> 204
cleanup: DELETE /items/125a34a9-3d42-4b73-bfd1-9379b97aae13 -> 204
cleanup: DELETE /items/4d1ded66-fe5d-4902-a8c2-4f594962e195 -> 204
exit 0
```

### Mục thử script đã publish (để giải thích số reload của widget)

Bốn mục `notification`, `source` `acceptance`, đều đã bị `DELETE` trong cùng phút. Thời điểm theo nhật ký `events`, giờ Asia/Saigon:

| seq | Sự kiện | Mục | Lúc |
|---|---|---|---|
| 448 | `item.created` | `f7958200…` (CLI publish) | 15:34:05.6 |
| 449 | `item.created` | `dd601128…` (dedupe) | 15:34:07.5 |
| 450–453 | `item.created`, `read`, `unread`, `deleted` | `125a34a9…` | 15:34:08.6–15:34:12.4 |
| 454 | `item.created` | `4d1ded66…` (ttl mặc định) | 15:34:18.0 |
| 455–457 | `item.deleted` | `f7958200…`, `dd601128…`, `4d1ded66…` | 15:34:18.7–15:34:19.5 |

Tổng cộng 4 `item.created`, 1 `item.read`, 1 `item.unread`, 4 `item.deleted`, trong khoảng 15:34:05–15:34:20. Cron không tạo mục nào vì bảng từ rỗng.

## CPU của các lần chạy cron

Đo bằng `npx wrangler@4.166.0 tail os-widget --format json`, ghi ra thư mục scratchpad ngoài repo. Có ba cửa sổ tail:

- Cửa sổ 1: 15:33:52–16:39:52. Bị rớt kết nối một lần và tự nối lại, không mất lần chạy nào.
- Cửa sổ 2: từ 15:45:54. Âm thầm ngừng nhận sự kiện sau 16:00:31, nên chỉ trùng với cửa sổ 1.
- Cửa sổ 3: 16:52 đến khi dừng lúc 17:02, theo yêu cầu của supervisor để session widget kiểm khi tắt Wi‑Fi.

Ba lần 16:40, 16:45 và 16:50 rơi vào khoảng trống giữa các cửa sổ nên không có số đo. Sự kiện cron được gộp theo `scheduledTime`.

| Lần chạy | cpuTime (ms) | wallTime (ms) | outcome | Log |
|---|---|---|---|---|
| 15:45 | 13 | 744 | ok | `vocab.tick status=empty` |
| 15:50 | 7 | 1035 | ok | `vocab.tick status=empty` |
| 15:55 | 9 | 843 | ok | `vocab.tick status=empty` |
| 16:00 | 17 | 962 | ok | `vocab.tick status=empty` |
| 16:05 | 6 | 875 | ok | `vocab.tick status=empty` |
| 16:10 | 11 | 598 | ok | `vocab.tick status=empty` |
| 16:15 | 7 | 859 | ok | `vocab.tick status=empty` |
| 16:20 | 9 | 456 | ok | `vocab.tick status=empty` |
| 16:25 | 5 | 868 | ok | `vocab.tick status=empty` |
| 16:30 | 8 | 545 | ok | `vocab.tick status=empty` |
| 16:35 | 14 | 1194 | ok | `vocab.tick status=empty` |
| 16:55 | 6 | 885 | ok | `vocab.tick status=empty` |
| 17:00 | 9 | 678 | ok | `vocab.tick status=empty` |

Tóm tắt:

- 13 lần chạy, trải trên 75 phút.
- `cpuTime` p50 9 ms (nearest-rank), nhỏ nhất 5 ms, lớn nhất 17 ms, trung bình 9,3 ms.
- `wallTime` p50 859 ms, lớn nhất 1194 ms. Phần lớn là chờ RPC tới Supabase, không tính vào CPU.
- `outcome` khác `ok`: 0. `exceededCpu`: 0. Không có exception.
- 4/13 lần vượt 10 ms (11, 13, 14 và 17 ms), vượt hạn mức CPU 10 ms của gói Free mà vẫn `ok`. Điều này giống cold start ở M0 (16–21 ms, không bị chặn). Cron 5 phút một lần thường rơi vào isolate lạnh.
- Mọi lần chạy đều trả `status=empty`, đúng như dự kiến khi `vocab_words` rỗng.

Lưu ý: chưa đo lần chạy `sent` (có chèn mục và ghi `settings`) và chưa đo `POST /vocab/words`. Cả hai cần dữ liệu thật ở G3. Phần CPU của Worker gần như không đổi theo trạng thái, vì Worker chỉ gọi một RPC và giải mã một object nhỏ, nhưng nên đo lại khi G3 chạy.

## `scripts/acceptance-vocab.sh`

Cách gọi: `scripts/acceptance-vocab.sh <worker-url> [2] [3] [4] [5]`. Không ghi tiêu chí nào thì chạy cả bốn.

Biến môi trường:

- `PUBLISH_TOKEN` cho tiêu chí 2 và 3.
- `CLIENT_TOKEN` cho tiêu chí 4.
- `SUPABASE_DB_URL` bắt buộc cho tiêu chí 3, 4 và 5, tuỳ chọn cho tiêu chí 2.

Token đi qua file header mode 600 trong thư mục tạm mode 700. Chuỗi kết nối DB được tách thành biến `PG*` cho `psql`, không nằm trên dòng lệnh. Script in `PASS`/`FAIL` cho từng tiêu chí và thoát 1 nếu có `FAIL`. Khi bị dừng giữa chừng, script vẫn trả lại `vocab_interval_minutes` và dừng stack Supabase cục bộ nếu chính nó đã bật. Viết cho bash 3.2 của macOS. `bash -n` và `shellcheck` sạch.

Lần chạy này chỉ chạy tiêu chí 5, lúc 15:37:03–15:37:17, mã thoát 0. Script bật stack cục bộ rồi dừng lại. Đầu ra:

```text
vocab acceptance against https://os-widget.longdaobk17.workers.dev, criteria 5
PASS 5 when words run out: local pgTAP: Files=1, Tests=69,  0 wallclock secs ( 0.01 usr +  0.00 sys =  0.01 CPU) Result: PASS;live vocab_when_exhausted 'rotate' (want 'rotate'); vocab-cron items without a word or meanings: 0
checks failed: 0
stopped the local Supabase stack
exit 0
```

Một lần chạy thử trước đó, không có `SUPABASE_DB_URL` do lỗi trong lệnh dựng chuỗi kết nối của tôi, cho `FAIL 5 … live check needs SUPABASE_DB_URL` và mã thoát 1. Điều này cho thấy nhánh thiếu biến báo lỗi đúng.

Tiêu chí 2, 3 và 4 chưa chạy lần nào, vì chúng nạp từ và đổi `settings` trên live. Session sau chạy lần đầu cũng là lần kiểm chính các nhánh đó.

## Trạng thái live khi kết thúc (17:02)

- `vocab_words`: 0 dòng.
- `settings`: đúng sáu giá trị mặc định ở trên; `vocab_last_sent_at` vẫn `null`.
- Không có mục nào với `source = 'vocab-cron'`. Hai mục `kind = 'vocab'` có trên live là của session nghiệm thu khác: `acceptance-m3` lúc 16:28:30 và `acceptance-m2` lúc 16:48:49. Session này không tạo chúng.
- Không còn tiến trình `wrangler tail` nào. Stack Supabase cục bộ đã dừng.

## Còn lại

- **G3.** Nạp bộ từ đầu tiên sau khi đợt đếm reload 24 giờ kết thúc (2026-11-25 15:28:48):
  - `os-widget ingest words` với 17 từ đủ trường của lần đo cộng danh sách riêng của operator.
  - `os-widget ingest book <Pride and Prejudice> --origin "<tên>" --max 50`; xem `--dry-run` trước.
  - Đo CPU của `POST /vocab/words` và của một lần cron `status=sent`.
- **Tiêu chí 2 và 3.** `scripts/acceptance-vocab.sh <worker-url> 2 3`.
- **G4 và tiêu chí 4.** `scripts/acceptance-vocab.sh <worker-url> 4` đổi `vocab_interval_minutes` thành 5 rồi 15 trong khoảng 35 phút, và tự trả lại giá trị cũ. Trong thời gian đó, cứ 5 phút lại có một thẻ `normal` bật popup. Nên báo operator trước.
- Ghi số CPU vào `docs/architecture.md` §8 ở Phase 10.

## Câu hỏi còn mở

Không có.
