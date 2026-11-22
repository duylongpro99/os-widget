---
phase: 4
title: "Khung Rust và deploy"
status: pending
priority: P1
effort: "3h"
dependencies: [2]
---

# Phase 4: Khung Rust và deploy

## Goal

Dựng Cargo workspace có crate `envelope` và crate `worker` đúng bố cục `docs/architecture.md` §4.2, deploy lên gói miễn phí, sao cho `POST /items` ghi được vào Supabase và `GET /events?since=` đọc lại được. Khung này được giữ làm khởi đầu cho Giai đoạn 1.

## Files to Create / Modify

- Create: `Cargo.toml` (workspace, `[profile.release]` có `opt-level = "z"`, `lto = true`, `codegen-units = 1`)
- Create: `crates/envelope/Cargo.toml`, `crates/envelope/src/lib.rs`
- Create: `crates/worker/Cargo.toml`, `crates/worker/src/lib.rs`
- Create: `crates/worker/wrangler.toml`

## Tasks & Steps

- [ ] `envelope`: struct `Envelope` với các trường ở §3.1 (`v`, `kind`, `source`, `priority`, `title`, `summary`, `url`, `ttl`, `dedupe_key`). `body` là enum gắn thẻ theo `kind` (`#[serde(tag = "kind", content = "body")]` hoặc tương đương), hiện chỉ có biến thể `Notification { text: Option<String> }`. Chỉ phụ thuộc `serde`.
- [ ] Unit test cho `envelope`: một envelope `notification` hợp lệ deserialize được; thiếu `title` thì lỗi; `kind` lạ thì lỗi.
- [ ] `worker`: phụ thuộc `worker`, `serde`, `serde_json`, `envelope`, và `uuid` (features `v4`, `js`) để sinh `id`. Không dùng `reqwest` hay `postgrest-rs`.
- [ ] Một token tạm `SPIKE_TOKEN` (Worker secret) kiểm ở cả hai endpoint qua header `Authorization: Bearer`. Giai đoạn 1 thay bằng hai token publish và client.
- [ ] `POST /items`: deserialize body thành `Envelope` (lỗi thì trả 400), sinh `id`, đổi `ttl` thành `expires_at` (mặc định 30 ngày), gọi `POST {SUPABASE_URL}/rest/v1/items` với header `apikey`, `Authorization: Bearer <service role>` và `Prefer: return=representation`, rồi trả `{ "id": ... }`.
- [ ] `GET /events?since=<seq>`: gọi `GET /rest/v1/events?seq=gt.<since>&order=seq.asc`, sau đó lấy các mục của sự kiện `item.created` bằng `GET /rest/v1/items?id=in.(...)`, và trả mảng sự kiện kèm mục.
- [ ] `wrangler.toml`: `compatibility_date` là ngày deploy, lệnh build `worker-build --release`, `[observability] enabled = true`, `SUPABASE_URL` đặt ở `[vars]`.
- [ ] Đặt secret: `npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY` và `npx wrangler secret put SPIKE_TOKEN`.
- [ ] Deploy: `npx wrangler deploy`. Ghi URL Worker và dòng dung lượng gửi lên (tổng và gzip) mà wrangler in ra.

## Verification

- `cargo test -p envelope` pass.
- `cargo build -p worker --target wasm32-unknown-unknown --release` thành công.
- `curl -X POST <url>/items -H "Authorization: Bearer $SPIKE_TOKEN" -d '{"v":1,"kind":"notification","source":"m0","title":"hello","summary":"m0 smoke","body":{"text":"hi"}}'` trả về `id`.
- `curl "<url>/events?since=0" -H "Authorization: Bearer $SPIKE_TOKEN"` có một sự kiện `item.created` kèm đúng mục đó.
- Request không có token nhận 401.
- `git status` không liệt kê secret.

## Risk Assessment

- `workers-rs` không build hoặc không gọi được fetch: đây là tín hiệu trượt của D. Ghi lại lỗi nguyên văn rồi chuyển sang nhánh TypeScript ở Phase 5.
- Gói Wasm vượt hạn mức ngay từ đầu: deploy sẽ bị từ chối. Thử các bước tối ưu ở Phase 5 trước khi kết luận.
- Cách gắn thẻ `body` theo `kind` trong serde không khớp đúng JSON ở §3.1: giữ nguyên JSON của §3.1 và đổi cách khai báo kiểu, không đổi định dạng.
