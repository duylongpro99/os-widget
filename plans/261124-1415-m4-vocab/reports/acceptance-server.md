# Nghiệm thu server M4: migration, deploy Cron Trigger, nạp từ, tiêu chí 2–5, đo CPU

Phần 1 (G1, G2, tiêu chí 5, CPU cron `empty`): session `m4-vocab-p07-live`, ngày 2026-11-24. Phần 2 (G3, tiêu chí 2–4, CPU `POST /vocab/words` và cron `sent`): session `m4-vocab-p07-live-2`, từ 2026-11-26 22:00 đến 2026-11-27 08:57. Giờ ghi theo Asia/Saigon. Nhánh `vocab-acceptance`, worktree `/Users/onedayin20902/personal/os-widget-wt/vocab-acceptance`.

## Kết luận

G1 và G2 đạt. Migration `20261124000000_vocab.sql` đã lên project live sau khi sao lưu. Worker chạy Cron Trigger `*/5 * * * *`, và `scripts/acceptance-server.sh` vẫn pass 8/8. Đã ghi được 13 lần chạy cron từ 15:45 đến 17:00: tất cả có `outcome` `ok`, trả `vocab.tick status=empty`, CPU p50 9 ms và lớn nhất 17 ms. Không lần nào `exceededCpu`, nên không cần đường dự phòng `pg_cron` (G5). Tiêu chí 5 PASS. Tiêu chí 2 đến 4 (G3, G4) để lại cho session sau, vì đợt đếm reload 24 giờ của widget đang chạy.

Phần 2: G3 đạt. Nạp 17 từ mẫu được `stored 17, skipped 0`; nạp 50 từ "Pride and Prejudice" được `stored 45, skipped 5`. Tiêu chí 2 và 3 PASS. Tiêu chí 4 chỉ đạt một nửa: đổi chu kỳ sang 5 phút có hiệu lực ngay ở lần cron kế tiếp mà không deploy (131 thẻ, khoảng cách 299–301 giây). Phần 15 phút chưa chạy, vì máy ngủ qua đêm làm script treo ở `sleep 900`. Vì vậy chu kỳ 5 phút và `priority` `low` nằm trên live từ 22:03 đến **08:56:41 ngày 2026-11-27**. Đó là lúc cả sáu khoá được trả về giá trị đã lưu (trừ `vocab_last_sent_at`). Cron lúc gửi thật (`status=sent`) đo được 2 lần, 9 và 17 ms, đều `ok`. `POST /vocab/words` có 6 request, p50 7 ms, lớn nhất 28 ms, đều `ok`. Không có `exceededCpu`, nên không làm G5. Trong đêm, bộ 62 từ quay vòng hai lần trên live, không gửi lại ngay từ vừa gửi và không có mục rỗng. Đây là bằng chứng live thêm cho tiêu chí 5.

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

## Trạng thái live khi kết thúc phần 1 (2026-11-24 17:02)

- `vocab_words`: 0 dòng.
- `settings`: đúng sáu giá trị mặc định ở trên; `vocab_last_sent_at` vẫn `null`.
- Không có mục nào với `source = 'vocab-cron'`. Hai mục `kind = 'vocab'` có trên live là của session nghiệm thu khác: `acceptance-m3` lúc 16:28:30 và `acceptance-m2` lúc 16:48:49. Session này không tạo chúng.
- Không còn tiến trình `wrangler tail` nào. Stack Supabase cục bộ đã dừng.

## Phần 2: G3, tiêu chí 2–4 và CPU (2026-11-26 22:00 – 2026-11-27 08:57)

Lấy token và mật khẩu DB từ Keychain ngay trong lệnh cần. `SUPABASE_DB_URL` được dựng trong môi trường của lệnh chạy script, không in ra và không ghi vào file. Lệnh `npx wrangler@4.166.0 tail os-widget --format json` ghi ra scratchpad ngoài repo, từ 22:00 đến khi mất kết nối.

### Giá trị lưu trước khi đổi dữ liệu live (22:00:07)

| key | value |
|---|---|
| `vocab_enabled` | `true` |
| `vocab_interval_minutes` | `60` |
| `vocab_item_ttl_seconds` | `86400` |
| `vocab_last_sent_at` | `null` |
| `vocab_priority` | `"normal"` |
| `vocab_when_exhausted` | `"rotate"` |

`vocab_words`: 0 dòng.

### G3: nạp bộ từ đầu tiên

**17 từ mẫu.** Đây là 17 từ đủ trường của lần đo API (`reports/api-coverage.md`), tức 20 mẫu trừ `resilient`, `vindicate`, `lanterns`: ambiguous, benevolent, candid, eloquent, ephemeral, garrulous, lucid, meticulous, mitigate, ostentatious, pragmatic, quintessential, scrutinize, serendipity, tenacious, ubiquitous, wandered. Operator không có danh sách riêng. Lệnh `os-widget ingest words` (origin mặc định `dictionaryapi.dev`) chạy lúc 22:01:06–22:01:15 và cho `stored 17, skipped 0`.

**Sách.** Trên máy không có bản sẵn. `www.gutenberg.org` đang bảo trì (trả trang HTML "Temporarily Down for Maintenance"), nên đã tải `1342-0.txt` (UTF-8, 738046 byte, có dòng `*** START OF` và `*** END OF`) từ mirror chính thức `gutenberg.pglaf.org/1/3/4/1342/`. File nằm trong scratchpad ngoài repo và không được commit.

Lần `--dry-run` đầu trên cả file cho 50 từ, đều lấy từ lời tựa năm 1894 của George Saintsbury trong bản George Allen, chưa tới văn bản của Austen: acknowledgment, friendship, advice, illustrations, gratefully, somewhere, distinction, loving, allowance, personal, applies, books, women, numerous, objects, brings, curious, consequence, difference, loved, convention, proper, fairly, large, choice, probably, claim, novels, delightful, humour, finish, undoubted, critical, facts, scale, small, scheme, reached, difficulty, faint, interest, exquisite, delicacy, keeping, heroine, insipid, author, destroyed, romantic, expressly.

Vì thế đã nạp từ một bản cắt bỏ phần đầu. Bản này giữ dòng `*** START OF`, rồi lấy từ dòng `Chapter I.]` (dòng 675) đến hết file. Không sửa chữ nào trong văn bản. `--dry-run` trên bản này cho 50 từ từ Chương I trở đi: truth, universally, acknowledged, single, possession, fortune, views, entering, neighbourhood, fixed, minds, surrounding, families, considered, property, daughters, returned, impatiently, objection, hearing, invitation, large, north, chaise, delighted, agreed, servants, thousand, girls, affect, tiresome, thinking, marrying, design, settling, likely, visit, comes, occasion, handsome, flatter, share, beauty, pretend, extraordinary, grown, cases, engage, assure, consider. Ví dụ ngữ cảnh của `truth`: "It is a truth universally acknowledged, that a single man in possession of a good fortune must be in want of a wife."

Lệnh `os-widget ingest book <bản cắt> --origin "Pride and Prejudice" --max 50` chạy lúc 22:01:49–22:02:31 và cho `stored 45, skipped 5`:

- `acknowledged`, `neighbourhood`, `families`: `missing ipa`.
- `invitation`, `consider`: `dictionary error 429`, sau khi CLI đã thử lại. Hai lần 429 trong 50 lần tra không phải 429 kéo dài, nên không dừng.

Sau G3: `dictionaryapi.dev` 17 dòng, `Pride and Prejudice` 45 dòng; mọi dòng có `context`.

### Tiêu chí 2 và 3

Lệnh `scripts/acceptance-vocab.sh https://os-widget.longdaobk17.workers.dev 2 3` chạy lúc 22:02:39–22:02:47, mã thoát 0:

```text
vocab acceptance against https://os-widget.longdaobk17.workers.dev, criteria 2 3
PASS 2 ingest words: first run 'stored 3, skipped 1', second run 'stored 3, skipped 1'; rows 62 before the second run, 62 after; 3 of the four words stored
PASS 3 ingest book: 'stored 1, skipped 2'; 1 words with origin acceptance-book, each with a sentence from the book (wandered)
checks failed: 0
```

`serendipity`, `meticulous`, `garrulous` đã có từ G3. Lần nạp đầu của tiêu chí 2 ghi đè `origin` thành `acceptance-words` mà không thêm dòng. Lần nạp lại giữ nguyên 62 dòng. `wandered` (đã có) nhận thêm câu ngữ cảnh từ `sample.txt` và đổi `origin` thành `acceptance-book`, đúng quy tắc ghi đè đã chốt. Sau bước này live có 62 từ. Sau đó không có lần nạp nào nữa.

### G4 và tiêu chí 4

Một wrapper đặt `vocab_priority` thành `"low"` lúc 22:03:02, rồi chạy `scripts/acceptance-vocab.sh <worker-url> 4`. Script ghi `vocab_interval_minutes was 60`, đặt 5 và bắt đầu `sleep 900`. Máy ngủ ngay sau đó. `sleep` của macOS không đếm thời gian máy ngủ, nên script treo ở bước này suốt đêm và không bao giờ đặt 15.

Supervisor phát hiện lúc 08:56. Theo lệnh của supervisor, các bước làm theo thứ tự:

1. Trả cả năm khoá cấu hình về giá trị đã lưu trong một transaction. Commit lúc **2026-11-27 08:56:41**.
2. Đọc lại cả sáu khoá lúc 08:56:42 (bảng dưới).
3. Dừng script và wrapper bằng `kill -9`, để trap của chúng không ghi thêm gì vào live (giá trị trap sẽ ghi cũng chính là giá trị cũ).

Từ 08:56:41, session này không ghi gì lên live. Sau mốc đó chỉ có một lần đọc `GET /events` để chấm tiêu chí 4, theo yêu cầu của supervisor.

Kết quả từ `GET /events` (từ seq 489), các mục `item.created` có `source = 'vocab-cron'`:

- 131 mục, từ 22:05:32 (seq 510) đến 08:55:31 (seq 640). Mọi mục có `priority` `low`.
- Khoảng cách giữa hai mục kế tiếp: nhỏ nhất 299 giây, lớn nhất 301 giây.
- Mục đầu tiên tới ở lần cron đầu tiên sau khi đổi (22:05), không deploy.
- Ngoài các mục này, đêm đó không có `item.created` nào khác.

| Phần | Kết quả |
|---|---|
| Đặt 5 phút: có ít nhất 2 mục cách nhau khoảng 5 phút | **PASS.** 131 mục, khoảng cách 299–301 giây; có hiệu lực ngay lần cron kế tiếp, không deploy. |
| Đặt 15 phút: khoảng cách ≥ 14 phút | **Chưa làm.** Không có bằng chứng, vì script treo trước khi đặt 15. |

Ngoài ra, việc trả về 60 lúc 08:56:41 cũng là một lần đổi chu kỳ không cần deploy. Nếu nó có hiệu lực, mục kế tiếp sẽ tới khoảng 09:55, và không có mục nào lúc 09:00–09:50. Session này không kiểm điều đó, vì không được chạm live sau mốc trả lại.

`scripts/acceptance-vocab.sh` đã sửa: hai lần chờ của tiêu chí 4 dùng `wait_for`, đếm theo đồng hồ thực (`date +%s`) với bước `sleep 10`. Nếu máy ngủ, script kết thúc bước chờ ngay khi máy thức thay vì kéo dài thêm. `bash -n` và `shellcheck` sạch. Bản sửa chưa chạy trên live.

### Bằng chứng live thêm cho tiêu chí 5 (quay vòng)

Bộ 62 từ cạn lúc 03:10 và lúc 08:20 (5 giờ 10 phút cho mỗi vòng ở chu kỳ 5 phút). Ở cả hai lần, cron gửi tiếp từ đầu vòng mới. Hai mục liên tiếp không bao giờ cùng một từ, và không có mục rỗng hoặc lỗi. Điều này khớp `vocab_when_exhausted = "rotate"`.

### CPU

Đo từ tail. Tail mất kết nối nhiều lần (keep-alive), rồi ngừng hẳn sau 5 lần thử nối lại, chắc do máy ngủ. Tail chỉ có sự kiện tới 23:05.

`POST /vocab/words`: 6 request, đều `ok`, status 200.

| Lúc | Lô | Body (byte) | cpuTime (ms) |
|---|---|---|---|
| 22:01:14 | 17 từ mẫu | 7888 | 20 |
| 22:02:13 | sách, lô 25 từ | 17760 | 28 |
| 22:02:31 | sách, lô 20 từ | 13122 | 5 |
| 22:02:41 | tiêu chí 2, lần 1 (3 từ) | 1513 | 7 |
| 22:02:44 | tiêu chí 2, lần 2 (3 từ) | 1513 | 27 |
| 22:02:46 | tiêu chí 3 (1 từ) | 640 | 5 |

Tóm tắt: p50 7 ms (nearest-rank), lớn nhất 28 ms; 3/6 vượt 10 ms mà vẫn `ok`. Hai request 3 từ giống hệt nhau cho 7 và 27 ms, nên phần vượt chủ yếu đến từ isolate lạnh, không đến từ cỡ lô.

Cron `vocab.tick status=sent`: tail bắt được 2 lần, 22:05:31 (cpuTime 9 ms, wallTime 1482 ms) và 23:05:31 (17 ms, 1019 ms), đều `ok`. p50 9 ms, lớn nhất 17 ms, giống các lần `empty` ở phần 1 (p50 9, lớn nhất 17). Toàn bộ tail không có `outcome` khác `ok`, không `exceededCpu`, không exception. 129 lần gửi còn lại không có số CPU, nhưng cả 131 lần đều tạo được mục đúng giờ.

### Trạng thái live khi kết thúc (2026-11-27 08:56:42)

| key | value | so với 22:00:07 |
|---|---|---|
| `vocab_enabled` | `true` | bằng |
| `vocab_interval_minutes` | `60` | bằng |
| `vocab_item_ttl_seconds` | `86400` | bằng |
| `vocab_last_sent_at` | `"2026-11-27T01:55:31.870248+00:00"` (08:55:31) | đổi do cron gửi, được phép |
| `vocab_priority` | `"normal"` | bằng |
| `vocab_when_exhausted` | `"rotate"` | bằng |

- `vocab_words`: 62 từ, gồm `dictionaryapi.dev` 13, `Pride and Prejudice` 45, `acceptance-words` 3, `acceptance-book` 1. Số 62 đọc lúc 22:02:57; sau đó không có lần nạp nào, và cron chỉ ghi `sent_at`.
- Không còn tiến trình `wrangler tail`, script nghiệm thu hay wrapper nào. Session này không bật stack Supabase cục bộ.

## Còn lại

- **Tiêu chí 4, phần 15 phút.** Đặt `vocab_interval_minutes` thành 15 và thấy khoảng cách ≥ 14 phút. Cần một lần chạy mới của `scripts/acceptance-vocab.sh <worker-url> 4` (đã sửa phần chờ), có `vocab_priority` `low` trong lúc kiểm. Chỉ chạy khi supervisor cho phép, vì đợt đếm reload 12 giờ của widget bắt đầu từ 08:56:41.
- **Số CPU vào `docs/architecture.md` §8** ở Phase 10. Cron `empty`: p50 9 ms, lớn nhất 17 ms (13 lần). Cron `sent`: 9 và 17 ms (2 lần). `POST /vocab/words`: p50 7 ms, lớn nhất 28 ms (6 lần).
- Danh sách 50 từ của `ingest book` trên bản Gutenberg đầy đủ lấy toàn bộ từ lời tựa. Muốn dùng file nguyên bản cho sách khác có lời tựa, cần cắt tay như ở trên, hoặc thêm vào CLI một cách bỏ phần front matter. Việc này ngoài phạm vi Phase 7.

## Câu hỏi còn mở

- Đêm 26/11 widget nhận 131 thẻ `low` 5 phút một lần, thay vì thẻ `normal` mỗi giờ. Vì vậy đêm này không dùng được làm bằng chứng cho mục 7 của checklist widget. Có cần một đêm khác ở cấu hình mặc định không?
