# Báo cáo review: CLI `ingest words` từ Free Dictionary API

Nhánh `vocab-ingest-words` (head `555c0ad`, tách từ `bd14774`) đạt yêu cầu và đã merge vào `main` bằng `--no-ff` tại `e0ade92`. Review không tìm thấy lỗi phải sửa, nên không có commit sửa nào trên nhánh. Chỉ còn hai góp ý nhỏ, ghi ở dưới, không chặn merge.

## Phạm vi đã đọc

`plan.md`, phase 5, phase 4 (hợp đồng `POST /vocab/words`), báo cáo cook `p05-cook.md`, toàn bộ diff `bd14774..555c0ad` (`crates/cli/src/main.rs`, `crates/cli/src/ingest/mod.rs`, `crates/cli/src/ingest/dictionary.rs`, 6 fixture) và `crates/envelope/src/vocab.rs`.

## Các điểm brief yêu cầu kiểm

| Điểm | Kết quả |
|---|---|
| Mã thoát | Khớp quy ước của `publish`. Server trả 400 hoặc `origin` sai cục bộ cho mã 2 (`EXIT_INVALID`, tiền tố `invalid vocab:`). Các lỗi 401, 403, 5xx, lỗi mạng, thiếu server hoặc token, không đọc được file hoặc file không phải UTF-8 cho mã 1 (`Report::failure`). 200 không có `stored` cũng cho mã 1. |
| Token | Chỉ đọc từ `OS_WIDGET_PUBLISH_TOKEN` (`resolve_token`). Không có cờ `--token`, và có test kiểm điều này. Token chỉ xuất hiện trong header `Authorization`. Mọi thông báo lỗi chỉ chứa URL, mã trạng thái và một đoạn body. `--dry-run` không đọc token. |
| Thử lại và giãn cách | Có giới hạn: `RETRY_WAITS.iter()` chỉ cho 3 lần thử lại 429 hoặc 5xx (chờ 1, 2, 4 giây), sau đó bỏ từ với lý do `dictionary error <status>`. Lỗi mạng và các mã khác không được thử lại. Thời gian giãn cách mỗi lần tối đa 300 ms. Không có vòng lặp nào chạy mãi. |
| Test không ra mạng | Test dùng fixture và `FakeServer` trên `127.0.0.1:0`. Server này dừng trong `Drop` (đánh dấu dừng, kết nối để mở khoá `accept`, rồi `join`). Test ở `main.rs` chỉ parse cờ, không test nào gọi `DEFAULT_URL`. |
| Hợp đồng phase 4 | Body `{"origin", "words"}` với lô 25 từ, dưới giới hạn 50 của server. Lỗi 400 được đọc qua `field` và `message`. Mọi body được kiểm bằng `envelope::check_vocab`, và test gửi thật chạy `envelope::parse_vocab` trên body nhận được. `"context": null` hợp lệ vì `VocabBody.context` có kiểu `Option<String>`. |
| Các khác biệt cook đã nêu | Supervisor đã chấp nhận và mã khớp với mô tả: dry-run in mảng JSON ra stdout, dòng không phải từ bị bỏ với lý do `invalid characters`, dừng ở lô lỗi đầu tiên kèm `stored/skipped`, `origin` rỗng hoặc dài hơn 200 ký tự thoát mã 2. |

## Góp ý (không sửa, không chặn merge)

1. **DRY, mức nit.** `ingest::interpret_batch_response` và `ingest::post_batch` lặp lại gần nguyên phần ánh xạ 400, 401, 403 và 5xx của `interpret_response` và `send` trong `main.rs`, chỉ khác tiền tố `invalid vocab` so với `invalid envelope`. Có thể gộp thành một hàm dùng chung khi phase 6 sửa lại `ingest/mod.rs`. Mã hiện tại vẫn đúng và có test, nên theo brief tôi không viết lại chỉ vì phong cách.
2. **Báo cáo tiến độ, mức nit.** Dòng `ok <word>` được in khi tra từ thành công, trước khi lô chứa từ đó được gửi. Nếu lô sau bị lỗi, vài từ đã in `ok` sẽ không được lưu. Dòng `stored n, skipped m` cuối cùng vẫn cho số đúng, nên chấp nhận được.

## Kiểm tra

- Trên nhánh: `cargo test -p cli` cho 69 test pass, `cargo clippy --workspace -- -D warnings` sạch, quét secret bằng `git grep` không thấy gì.
- Mutation: tôi bỏ việc loại từ khi `check_vocab` báo lỗi (`map_err(...)?` đổi thành `let _ = ...`). Kết quả là 1 test fail (`a_blank_part_of_speech_fails_the_shared_check`) và 68 pass. Tôi đã revert bằng `git checkout` và nhánh sạch trở lại.
- Trên `main` sau merge: `cargo test --workspace` cho 151 test pass, `cargo clippy --workspace -- -D warnings` sạch, `swift test` (OSWidgetKit) cho 149 test pass.
- Review này không gọi API từ điển thật, Worker, Supabase hay Cloudflare.

## Kết thúc

- Merge: `e0ade92`. Đã đánh dấu phase 5 `Completed` trong `plan.md` và trong file phase.
- Worktree `os-widget-wt/vocab-ingest-words` và nhánh `vocab-ingest-words` đã được gỡ. Chưa push.
- Vòng thử cục bộ với `wrangler dev` và Supabase (nạp lại không tăng số dòng) vẫn để dành cho phase 7, như báo cáo cook đã nêu.
