---
phase: 3
title: "Worker năm endpoint, hai token"
status: pending
priority: P1
effort: "4h"
dependencies: [1, 2]
---

# Phase 3: Worker năm endpoint, hai token

## Goal

Worker có đủ năm endpoint của architecture §4.1, phân quyền bằng hai token publish và client, trả lỗi validate nêu rõ trường, chống trùng theo `dedupe_key`, và phân trang `GET /events` bằng `limit`.

## Files to Create / Modify

- Modify: `crates/worker/src/lib.rs` (chỉ còn router và `#[event(fetch)]`)
- Create: `crates/worker/src/auth.rs`, `crates/worker/src/supabase.rs`, `crates/worker/src/items.rs`, `crates/worker/src/events.rs`
- Modify: `crates/worker/wrangler.toml` nếu cần (không đặt secret ở đây)

## Thiết kế đã chốt

**Token.** Hai secret `PUBLISH_TOKEN` và `CLIENT_TOKEN` thay cho `SPIKE_TOKEN`. `POST /items` cần token publish; bốn endpoint còn lại cần token client. So sánh hằng thời gian như M0, với cả hai token.

| Tình huống | Trả về |
|---|---|
| Không có header, sai dạng, hoặc không khớp token nào | 401 `{"error":"unauthorized"}` |
| Khớp token nhưng sai loại cho endpoint | 403 `{"error":"forbidden"}` |

Kiểm token trước khi route, như M0. Đường dẫn không tồn tại vẫn 404 sau khi qua kiểm token.

**Định dạng lỗi.** Mọi lỗi là JSON `{"error": "<mã>"}`; lỗi validate thêm `field` và `message` lấy từ `envelope::EnvelopeError`: `400 {"error":"invalid envelope","field":"body.meanings[0]","message":"missing field `definition`"}`.

**`POST /items`.**

- Parse bằng `envelope::parse`. Giữ kiểm `ttl` vượt phạm vi ngày của JS từ M0 (`field: "ttl"`).
- Không có `dedupe_key`: insert như M0, trả 201 `{"id": ...}`.
- Có `dedupe_key`: insert với `?on_conflict=dedupe_key` và `Prefer: resolution=ignore-duplicates,return=representation`. Nhận một dòng → 201 `{"id": ...}`. Nhận mảng rỗng → đọc `items?dedupe_key=eq.<key>&select=id` (mã hoá URL cho khoá) và trả 200 `{"id": ...}` của mục đã có, kể cả khi mục đó đã bị xoá mềm. Trigger chỉ chạy khi có dòng được thêm, nên không sinh sự kiện trùng.
- Mặc định `ttl` đổi từ 30 ngày (M0) thành 7 ngày: `DEFAULT_TTL_SECS = 7 * 24 * 60 * 60`. <!-- Updated: Validation Session 1 - ttl mặc định 7 ngày -->

**`GET /items`.** Đọc `seq` lớn nhất trước (`events?select=seq&order=seq.desc&limit=1`, rỗng thì 0), sau đó đọc các mục còn hiệu lực (`deleted_at=is.null` và `expires_at` rỗng hoặc lớn hơn thời điểm hiện tại), sắp `created_at.desc`. Trả `{"seq": <n>, "items": [...]}`. Thứ tự hai lần đọc đảm bảo client không bỏ sót: sự kiện xảy ra giữa hai lần đọc sẽ được `GET /events?since=<seq>` trả lại, và áp dụng lại là idempotent.

**`GET /events?since=<seq>&limit=<n>`.** `since` bắt buộc, số nguyên ≥ 0. `limit` mặc định 100; lớn hơn 100 thì hạ về 100; nhỏ hơn 1 hoặc không phải số thì 400 `{"error":"invalid limit"}`. Truy vấn `events?seq=gt.<since>&order=seq.asc&limit=<n>`, rồi nhúng mục cho sự kiện `item.created` như M0 (mục đã bị xoá hẳn cho `item: null`). Giữ dạng trả về là mảng sự kiện.

**`PATCH /items/{id}`.** Body `{"read": true}` hoặc `{"read": false}`; sai dạng thì 400 `{"error":"invalid body"}`.

- `read: true`: cập nhật `read_at` thành thời điểm hiện tại với điều kiện `id=eq.<id>&deleted_at=is.null&read_at=is.null`.
- `read: false`: cập nhật `read_at` thành `null` với điều kiện `id=eq.<id>&deleted_at=is.null&read_at=not.is.null`.
- Có dòng được cập nhật → 204. Không có dòng: đọc lại mục; mục tồn tại và chưa xoá → 204 (đã ở đúng trạng thái); không tồn tại hoặc đã xoá → 404 `{"error":"not found"}`. Xoá thắng đã đọc (architecture §5).

**`DELETE /items/{id}`.** Cập nhật `deleted_at` thành thời điểm hiện tại với điều kiện `id=eq.<id>&deleted_at=is.null`. Có dòng → 204. Không có dòng: mục tồn tại (đã xoá trước đó) → 204; không tồn tại → 404.

Client coi 404 của `PATCH` và `DELETE` là đã xong khi gửi lại hàng đợi (Giai đoạn 2). Ghi điều này vào architecture ở Phase 5.

**Id trong đường dẫn.** Chỉ nhận chuỗi có dạng UUID; sai dạng thì 404, không đưa vào truy vấn PostgREST.

**Logic thuần tách khỏi I/O** để test được trên máy thật (crate `worker` đã biên dịch được cho máy thật, `cargo test -p os-widget-worker` chạy được): phân loại token và quyền theo endpoint, parse `since` và `limit`, parse body `PATCH`, kiểm dạng UUID, dựng JSON lỗi từ `EnvelopeError`.

## Tasks & Steps

- [ ] Tách `lib.rs` thành các module ở trên; `supabase.rs` giữ hàm gọi PostgREST của M0, thêm tham số header `Prefer`.
- [ ] `auth.rs`: hai token, bảng quyền, 401/403.
- [ ] `items.rs`: `POST /items` (lỗi có `field`, chống trùng), `GET /items`, `PATCH /items/{id}`, `DELETE /items/{id}`.
- [ ] `events.rs`: `GET /events` với `limit`.
- [ ] Unit test cho các hàm thuần: token đúng loại, sai loại, không khớp, thiếu header; `limit` vắng, 50, 500, 0, `abc`; `since` âm, vắng; body `PATCH` đúng, thiếu `read`, `read` không phải bool; UUID đúng và sai.
- [ ] Chạy với `npx wrangler dev` trỏ vào project Supabase (secret đặt trong `crates/worker/.dev.vars`, `.gitignore` đã có `.dev.vars`): một vòng publish, đọc sự kiện, đã đọc, bỏ đọc, xoá, publish trùng khoá, publish sai định dạng, token sai loại. Xoá mềm dữ liệu thử sau khi xong.

## Verification

- `cargo test -p os-widget-worker` pass.
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` thành công.
- `cargo clippy --workspace -- -D warnings` sạch.
- Vòng kiểm bằng `wrangler dev` ở trên cho đúng mã trạng thái và sự kiện.

## Risk Assessment

- `Prefer: resolution=ignore-duplicates` cần PostgREST biết cột xung đột: luôn gửi `on_conflict=dedupe_key`; ràng buộc `unique` trên `dedupe_key` đã có từ M0.
- Hai mục cùng `dedupe_key` gửi đồng thời: ràng buộc `unique` giữ chỉ một dòng; request thua nhận mảng rỗng và đọc lại mục thắng.
- So sánh `expires_at` với thời điểm hiện tại cần mã hoá dấu `:` và `+` trong URL: tạo chuỗi ISO bằng `js_sys::Date` như M0 và mã hoá phần giá trị.
- `.dev.vars` lọt vào git: kiểm `git status` và `git check-ignore crates/worker/.dev.vars` trước khi commit.
