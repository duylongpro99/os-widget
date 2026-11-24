# Báo cáo cook phase 4: Worker nạp từ và Cron Trigger

Nhánh `vocab-worker-cron` (từ `main` tại aa527fc). Chưa deploy, chưa gọi Worker hay Supabase thật.

## Đã làm

- `crates/worker/src/supabase.rs` (6873695): thêm `rpc` cho hàm Postgres trả giá trị đơn; `rows` dùng chung hàm gửi.
- `crates/worker/src/vocab.rs`, `lib.rs` (9c45766): `POST /vocab/words`, `#[event(scheduled)]`.
- `crates/worker/wrangler.toml` (fe9e1f7): `[triggers] crons = ["*/5 * * * *"]`.

## Route và mã trạng thái

`POST /vocab/words` (token publish): 200 `{"stored":n}`; 400 `{"error":"invalid vocab","field","message"}`; 401 thiếu token; 403 token client; 405 method khác; 502 Supabase lỗi. Lô phải có `origin` 1 đến 200 ký tự và 1 đến 50 từ; một từ lỗi thì không ghi từ nào.

## Cron

Handler `scheduled` chỉ gọi `rpc/vocab_tick` với `{}` và ghi `vocab.tick status=<status>` (không có từ). Lỗi gọi RPC được `console_error!`, không panic.

## Kiểm thử

- `cargo test --workspace`: 197 pass (trước đó 187; worker 46).
- `cargo clippy --workspace -- -D warnings`: sạch.
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` và `worker-build --release`: thành công.
- Handler `scheduled` không có test chạy trực tiếp (cần runtime Workers); phần logic thuần được test: `tick_log_line` (mọi status của SQL, kết quả lạ, ký tự lạ, không lộ từ), `parse_batch`, `word_field`.

## Dung lượng

`worker-build` không in kích thước wasm, và hook `scout-block` chặn đọc thư mục `build/`. Số đo được là bản trước `wasm-opt` ở `target/`: 1,40 MiB chưa nén, 385 KiB sau gzip. Cần đo lại bản tối ưu ở phase 7.

## Lệch so với phase file

- Envelope báo trường thiếu trong `message` ("missing field `ipa`") với `field` rỗng, nên Worker ghép tên đó để ra `words[3].ipa` như phase file yêu cầu (`word_field`).
- Không chạy `wrangler dev --test-scheduled` (không có `wrangler` trên máy, và không có Supabase cục bộ): vòng kiểm cục bộ chuyển sang phase 7.
- `vocab_tick` cũng có trạng thái `exhausted` (ngoài các trạng thái brief liệt kê); log in nguyên trạng thái.
