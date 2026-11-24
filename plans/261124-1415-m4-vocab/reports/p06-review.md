# Báo cáo review: CLI `ingest book` từ sách `.txt`

Nhánh `vocab-ingest-book` (head `f5c8442`) đạt yêu cầu sau một sửa nhỏ về hiệu năng, và đã merge vào `main` bằng `--no-ff` tại `886b34a`. Không có phát hiện nào cần operator quyết định.

## Phạm vi đã đọc

`plan.md`, phase 6, báo cáo cook `p06-cook.md`, báo cáo review phase 5 (hai nit), toàn bộ `crates/cli/src/main.rs`, `ingest/mod.rs`, `ingest/book.rs` (đọc đủ phần mã, không đọc từng test) và diff `a727d85..f5c8442`. Trước khi merge đã merge `main` vào nhánh (không xung đột).

## Phát hiện

| # | Mức | Nội dung | Xử lý |
|---|---|---|---|
| 1 | Hiệu năng | `book::candidates` tìm câu ngữ cảnh cho mọi từ đủ điều kiện rồi mới cắt còn `--max`; mỗi lần tìm quét cả sách. Trên một văn bản tổng hợp 160 KB có 6000 từ đủ điều kiện, bản debug mất 9,4 giây. | Sửa ở `4db941d`: sắp theo vị trí trước, chỉ tìm ngữ cảnh cho tới khi đủ `--max`. Cùng đầu vào còn 0,08 giây; kết quả không đổi, 105 test của `cli` vẫn pass. |

## Các điểm brief yêu cầu kiểm

| Điểm | Kết quả |
|---|---|
| Nit (b) | Đúng. `flush` chỉ in `ok <từ>` sau khi `post_batch` trả `Ok`; lô lỗi trả `Err` trước vòng in. Đột biến: in `ok` trước khi gửi làm fail 2 test (`a_word_is_reported_ok_only_after_its_batch_is_stored`, `five_sample_words_store_four_and_skip_the_one_without_ipa`); đã revert. |
| Ánh xạ lỗi sau refactor | Giống nhau. `error_report(what, status, body)` giữ nguyên nhánh 400 (field và message, chỉ message, hoặc `HTTP 400: …`, mã 2), 401 và 403 kèm gợi ý, các mã khác mã 1; chỉ khác tiền tố `invalid envelope` hay `invalid vocab`. Test `error_report_maps_each_status_for_any_payload_kind` phủ cả hai. |
| Phân tích sách không panic | Chạy `--dry-run` với file rỗng, file chỉ có BOM, một dòng 200.000 ký tự, CRLF kèm gạch nối ngắt dòng (`lan-\r\nterns` được nối), `--min-length 0 --max 0`: đều thoát 0, không panic. File không phải UTF-8 thoát 2. |
| Giới hạn | Danh sách từ chức năng là hằng tĩnh (khoảng 165 từ); tối đa `--max` từ; câu ngữ cảnh tối đa 240 ký tự; lô 25 từ; thử lại API tối đa 3 lần. Bộ nhớ theo cỡ sách (một lần, trong bộ nhớ), chấp nhận được cho CLI. |
| Token | Chỉ đọc từ `OS_WIDGET_PUBLISH_TOKEN` (`resolve_token`), chỉ dùng ở header `Authorization`, không có cờ `--token` (có test), `--dry-run` không đọc token. |
| Test | Chỉ dùng fixture và máy chủ giả trên `127.0.0.1`. |
| Đột biến thứ hai | Bỏ bộ lọc độ dài câu ngữ cảnh làm fail 2 test (`a_word_with_no_sentence_long_enough_is_left_out`, `a_fragment_is_never_the_context`); đã revert. |
| KISS | Không có gì đáng viết lại. `run_candidates` dựng `WordList` và `HashMap` rồi gọi `run_words` chung với `words`, đủ gọn. |

## Sách thật

`gutenberg.org` vẫn trả trang bảo trì (HTTP 503, 913 byte) cho `https://www.gutenberg.org/cache/epub/1342/pg1342.txt`. Không dùng mirror, không lưu file nào vào repo. Chưa có số liệu `--dry-run` và `--dry-run --lookup` cho "Pride and Prejudice"; chạy ở phase 7. Khuyến nghị: giữ mặc định `--min-length 5` và `--max 50`, xem danh sách `--dry-run` trước khi nạp thật, và lưu ý các từ API thiếu IPA sẽ bị bỏ (ở fixture là 2 trên 7).

## Kiểm tra trên `main` sau merge

`cargo test --workspace` 187 pass, `cargo clippy --workspace -- -D warnings` sạch, `swift test` (OSWidgetKit) 168 pass.

## Chưa làm

Vòng thử cục bộ với `wrangler dev` và Supabase, và lần chạy trên sách thật, thuộc phase 7. Review này không gọi API từ điển, Worker, Supabase hay Cloudflare.
