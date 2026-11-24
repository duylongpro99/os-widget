---
phase: 4
title: "Worker: POST /vocab/words và Cron Trigger"
status: pending
priority: P1
effort: "3h"
dependencies: [2, 3]
---

# Phase 4: Worker: `POST /vocab/words` và Cron Trigger

Server-only. Không chạm `apps/`. Không deploy ở phase này.

## Goal

Worker có endpoint `POST /vocab/words` (token publish) ghi một lô từ đã kiểm qua RPC `vocab_upsert`, và handler `scheduled` gọi đúng một RPC `vocab_tick` mỗi lần cron chạy.

## Context

- Router và kiểm token ở `crates/worker/src/lib.rs` (`route`, `Route`, `Route::role`, `auth::classify`); PostgREST qua `supabase::rows`.
- RPC và kết quả của `vocab_tick` theo Phase 2; hàm kiểm `envelope::parse_vocab` theo Phase 3.
- CPU: isolate lạnh 16–21 ms (architecture §8). Handler `scheduled` không parse gì ngoài kết quả nhỏ của RPC.

## Files to Create / Modify

- Modify: `crates/worker/src/lib.rs` (route `/vocab/words`, `#[event(scheduled)]`)
- Create: `crates/worker/src/vocab.rs`
- Modify: `crates/worker/wrangler.toml` (`[triggers] crons = ["*/5 * * * *"]`, theo câu hỏi 5)

## Thiết kế

**`POST /vocab/words`.** Token publish (`Route::PostVocabWords.role()` là `Role::Publish`); method khác trên đường dẫn này trả 405.

- Body `{"origin": "<tên nguồn>", "words": [<body vocab>, ...]}`.
- `origin` không rỗng, tối đa 200 ký tự; `words` có 1 đến 50 phần tử. Sai → 400 `{"error":"invalid vocab","field":"origin"|"words","message":...}`.
- Mỗi phần tử qua `envelope::parse_vocab`; phần tử lỗi → 400 `{"error":"invalid vocab","field":"words[3].ipa","message":...}`, không ghi phần tử nào của lô.
- Hợp lệ: `POST rpc/vocab_upsert` với `{"p_origin":..., "p_words":[...]}` (các body đã giải mã và tuần tự lại, không gửi JSON thô). Trả 200 `{"stored": <n>}`. Supabase lỗi → 502 như các endpoint khác.

**Cron.** `#[event(scheduled)]` gọi `POST rpc/vocab_tick` với body `{}`, ghi `console_log!("vocab.tick status=… word=…")` (không ghi định nghĩa hay nội dung khác), lỗi thì `console_error!` và không panic. Không có logic chọn từ trong Rust.

**Logic thuần tách khỏi I/O** để test trên máy thật: parse và kiểm body `POST /vocab/words`, dựng JSON lỗi, định dạng dòng log từ kết quả RPC.

## Tasks & Steps

- [ ] Thêm `Route::PostVocabWords`, route và quyền; cập nhật test router trong `lib.rs` (đúng route, 405, token client bị 403).
- [ ] `vocab.rs`: handler endpoint và hàm `tick(env)`; unit test cho `origin` rỗng, quá dài, `words` rỗng, 51 phần tử, phần tử thứ tư thiếu `ipa` (`field` là `words[3].ipa`), lô hợp lệ.
- [ ] `#[event(scheduled)]` trong `lib.rs` gọi `vocab::tick`.
- [ ] `wrangler.toml`: thêm `[triggers]`.
- [ ] Chạy cục bộ với Supabase cục bộ (Phase 2): `supabase start`, đặt URL và khoá service role cục bộ trong `crates/worker/.dev.vars` (đã bị `.gitignore`), `npx wrangler dev --test-scheduled`:
  - `POST /vocab/words` với hai từ → 200 `{"stored":2}`; gửi lại → 200, bảng vẫn hai dòng;
  - `curl "http://localhost:8787/__scheduled?cron=*/5+*+*+*+*"` → log `vocab.tick status=sent`, `GET /events` có `item.created` của mục `vocab`; gọi lại → `status=not_due`.

## Verification

- `cargo test -p os-widget-worker` pass.
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` thành công.
- `cargo clippy --workspace -- -D warnings` sạch.
- Vòng kiểm cục bộ ở trên cho đúng mã trạng thái, số dòng và sự kiện.
- `git check-ignore crates/worker/.dev.vars` in đường dẫn (không lọt secret).

## Risk Assessment

- Tên macro và chữ ký handler `scheduled` của `worker` 0.9 có thể khác (`ScheduledEvent`, `ScheduleContext`): kiểm bằng `cargo doc -p worker --open` hoặc mã nguồn crate trong `~/.cargo/registry`, không đoán.
- Lô 50 từ có thể tốn vài ms CPU khi giải mã: CLI gửi lô 25 (Phase 5); CPU đo ở Phase 7.
- `.dev.vars` trỏ nhầm vào project live: phase này chỉ dùng Supabase cục bộ; kiểm `SUPABASE_URL` trong `.dev.vars` là `http://127.0.0.1:54321` trước khi chạy.

## Rollback

Revert commit; chưa có gì deploy.
