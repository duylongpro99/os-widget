# Review phase 4: Worker nạp từ và Cron Trigger

Nhánh `vocab-worker-cron` (head trước review e0bd440) đạt yêu cầu và đã merge vào `main` bằng `--no-ff` tại 81fef3a. Review tìm hai lỗi nhỏ, đã sửa trên nhánh, không có phát hiện nào cần operator quyết.

## Phát hiện và sửa

1. `TickResult` giải mã trường `word` mà không dùng, chỉ để có dòng `let _ = &tick.word;`. Đã bỏ trường và dòng đó; dòng log vẫn chỉ có trạng thái (f08400e).
2. Worker kiểm `origin` sau khi trim nhưng lưu chuỗi gốc chưa trim, nên `"  book.txt "` được lưu kèm khoảng trắng. CLI đã trim trước khi gửi. Worker giờ lưu bản đã trim, có test kèm theo (87486c1).

Merge `main` vào nhánh (381f054) để lấy schema `vocab_upsert` và `vocab_tick`; không có xung đột.

## Khớp hợp đồng CLI và route

Đọc cả hai phía (`crates/cli/src/ingest/mod.rs`, `crates/worker/src/vocab.rs`) và chạy 80 test `ingest` của CLI (có fake server): pass.

- CLI gửi `POST {server}/vocab/words` với `Bearer` token publish, body `{"origin","words"}`, lô 25 (dưới giới hạn 50 của route). CLI tự chặn `origin` rỗng hoặc dài hơn 200 ký tự, cùng giới hạn với Worker.
- Mã 200 trả `{"stored":n}`. `vocab_upsert` trả `integer`, PostgREST trả số trần, Worker giải mã thành `u64`, và CLI đọc `stored` bằng `as_u64`.
- Mã 400 trả `{"error":"invalid vocab","field","message"}`. `error_report` của CLI in `field: message`, hoặc chỉ `message` khi `field` rỗng (body không phải object), và thoát mã 2.
- Mã 401, 403 và 502 dùng chung đường `error()` với các route khác. CLI thêm gợi ý về token cho 401 và 403, và thoát mã 1.
- Token: `Route::PostVocabWords.role()` là `Publish`. Token client bị trả 403 sau bước route, giống `POST /items`.
- Lô bị từ chối không ghi gì: cả lô được kiểm trước khi gọi RPC. `vocab_upsert` là một câu `insert ... on conflict` trong một lời gọi hàm, nên một lô hợp lệ được ghi nguyên vẹn hoặc không ghi gì.
- Hàm chỉ cấp quyền `execute` cho `service_role`. Worker gọi bằng khoá service role.

## Cron

`scheduled` gọi đúng một RPC (`rpc/vocab_tick`, body `{}`) và ghi một dòng `vocab.tick status=<status>`. Dòng log không chứa từ: trạng thái bị lọc còn `[A-Za-z0-9_]`, tối đa 32 ký tự. Lỗi đi qua `console_error!`. Không có `unwrap` hay `expect` trên đường chạy, và hàm không trả `Result`, nên không panic. Ngoài lời gọi RPC, hàm chỉ giải mã một object JSON nhỏ.

## Không đổi

Các route cũ giữ nguyên, chỉ thêm một nhánh match. `supabase::rows` giữ hành vi cũ (tách `send` dùng chung). `wrangler.toml` chỉ thêm `[triggers] crons = ["*/5 * * * *"]`. Không có secret: chỉ có `SUPABASE_URL` công khai trong `[vars]`, giống trước. `scripts/acceptance-server.sh` không bị sửa và không gọi route mới.

## Mutation

Bỏ `Route::PostVocabWords` khỏi vai trò `Publish` (tức là chấp nhận token client) thì test `only_publishing_needs_the_publish_token` fail. Đã revert.

## Dung lượng bundle

Chưa đo được bản đã tối ưu ở đây. Hook `scout-block` của repo chặn mọi lệnh có đường dẫn `build/` hoặc `target/`, và máy không có `wrangler` lẫn `wasm-opt`. Số cook báo là bản trước `wasm-opt`: 1,40 MiB chưa nén, 385 KiB gzip, thấp hơn nhiều so với giới hạn 3 MB (nén) của gói miễn phí. Phase 7 cần đo bản deploy.

## Kiểm thử trên `main` sau merge

- `cargo test --workspace`: 197 pass, 0 fail.
- `cargo clippy --workspace -- -D warnings`: sạch.
- `swift test` (OSWidgetKit): 188 test pass.

## Câu hỏi còn mở

Không có.
