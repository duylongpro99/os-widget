# Báo cáo cook: `ingest book` từ sách `.txt`

Nhánh `vocab-ingest-book` (worktree `/Users/onedayin20902/personal/os-widget-wt/vocab-ingest-book`), tách từ `main` tại `a727d85`. Chưa merge.

## Kết quả

Lệnh `os-widget ingest book <PATH> --origin <tên sách>` đã chạy được: đọc sách UTF-8, chọn từ đáng học, gắn câu ngữ cảnh lấy từ sách, tra Free Dictionary API và gửi lô tới `POST /vocab/words`. Từ API không bổ sung đủ trường thì bị bỏ, không gửi từ chỉ có ngữ cảnh.

## Commit

| Commit | Nội dung |
|---|---|
| `56476aa` | Một hàm `error_report` dùng chung cho ánh xạ lỗi 400/401/403/5xx của `publish` và `ingest` (nit a). |
| `cec5537` | In `ok <từ>` chỉ sau khi lô chứa từ đó được lưu (nit b). |
| `0f54213` | `ingest book`: `book.rs`, `stopwords.rs`, lệnh con, fixture `sample.txt`, test. |

Test của từng nit fail trước thay đổi: `error_report_maps_each_status_for_any_payload_kind` không biên dịch khi chưa có `error_report`; `a_word_is_reported_ok_only_after_its_batch_is_stored` fail trên mã cũ (đã chạy thử trên mã cũ) và pass sau thay đổi.

## Cờ CLI mới

`ingest book PATH --origin NAME [--max 50] [--min-length 5] [--dictionary-url URL] [--server URL] [--dry-run] [--lookup]`. `--lookup` chỉ dùng cùng `--dry-run` (clap `requires`). `--dry-run` một mình in JSON `[{word, context}]`, không gọi mạng và không cần token; `--dry-run --lookup` tra API và in body, không gửi.

## Kiểm tra

- `cargo test --workspace`: 187 pass (105 ở `cli`; trước đó 151 toàn workspace, 69 ở `cli`); `cargo clippy --workspace -- -D warnings` sạch; `cargo fmt` sạch.
- Test dùng fixture và máy chủ giả trên `127.0.0.1`, không dùng mạng.
- Thủ công, `--dry-run --lookup` trên `sample.txt` với API thật (7 GET): chọn 7 từ, lưu được 5 (`wandered`, `gardens`, `theory`, `extraordinary`, `quiet`), bỏ 2 vì `missing ipa` (`harbours`, `lanterns`). Cả 5 body có ngữ cảnh lấy từ file.

## Chưa làm được

Kiểm thủ công với "Pride and Prejudice": `gutenberg.org` trả trang "Temporarily Down for Maintenance" (HTTP 200, 913 byte HTML) ở cả hai URL thử (`/cache/epub/1342/pg1342.txt`, `/ebooks/1342.txt.utf-8`), nên chưa có số liệu cho cuốn thật. Brief chỉ cho phép tải từ gutenberg.org nên không thử mirror khác. Vòng thử cục bộ với `wrangler dev` và Supabase cục bộ cũng chưa chạy (brief cấm gọi Worker thật và phạm vi không gồm `supabase/`); phần gửi lô được kiểm bằng máy chủ giả.

## Sai khác so với phase file

1. Cắt "300 từ phổ biến nhất" thành `min(300, số từ khác nhau / 10)` và chỉ áp cho từ xuất hiện nhiều hơn 2 lần. Lý do: sách thật có vài nghìn từ khác nhau nên vẫn là 300; nhưng fixture nhỏ có dưới 300 từ khác nhau, nếu cắt nguyên 300 thì loại sạch mọi từ và bước `--dry-run` trên `sample.txt` không in gì.
2. Từ không có câu nào dài từ 20 ký tự chứa dạng viết thường thì bị loại thay vì nạp không ngữ cảnh.
3. Không tách câu sau `Mr.`, `Mrs.`, `Ms.`, `Dr.`, `St.`, `Jr.`, `Sr.`, `Messrs.`; bỏ dấu `_` (in nghiêng của Gutenberg). Cả hai là chi tiết tách câu cần cho văn bản Gutenberg.
4. `--dry-run` không có `--lookup` in JSON `{word, context}` (không phải danh sách văn bản thuần).
5. Sách không phải UTF-8 thoát mã 2 (đúng phase file); `ingest words` giữ mã 1 như đã merge. File không đọc được thoát mã 1.
6. Tách `check_origin`, `resolve_target`, `read_text` khỏi `words` để `book` dùng chung (cùng file `ingest/mod.rs`).
7. Thứ tự từ: theo lần xuất hiện đầu tiên ở dạng viết thường.

## Câu hỏi còn mở

- Khi Gutenberg hoạt động lại: chạy `--dry-run` rồi `--dry-run --lookup` trên bản #1342 để chỉnh `--min-length`/`--max` và ghi số liệu (cần thêm một lần tải).
- Phase 7 nên xem danh sách `--dry-run` của sách thật trước khi nạp, vì các từ API thiếu IPA (như `lanterns`) sẽ bị bỏ.
