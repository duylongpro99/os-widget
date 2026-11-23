---
phase: 5
title: "Deploy, nghiệm thu và cập nhật tài liệu"
status: completed
priority: P1
effort: "2h"
dependencies: [1, 2, 3, 4]
---

# Phase 5: Deploy, nghiệm thu và cập nhật tài liệu

## Goal

Deploy Worker với hai token thật, gỡ `SPIKE_TOKEN`, kiểm sáu tiêu chí của Giai đoạn 1 bằng một script lặp lại được trên bản deploy, và ghi lại những quyết định của M1 vào tài liệu.

## Files to Create / Modify

- Create: `scripts/acceptance-server.sh`
- Modify: `scripts/measure-worker.sh` (đổi `SPIKE_TOKEN` thành `PUBLISH_TOKEN` cho `POST` và `CLIENT_TOKEN` cho `GET`; lấy `seq` lớn nhất từ `GET /items` thay cho lệnh dò `GET /events?since=0&probe=1`, vì với `limit` lệnh dò đó chỉ thấy 100 sự kiện đầu)
- Modify: `docs/architecture.md`, `docs/roadmap.md`
- Modify: `docs/prd.md` (§11 câu 3: chốt `ttl` mặc định 7 ngày) <!-- Updated: Validation Session 1 - ttl mặc định 7 ngày -->

## Tasks & Steps

### Deploy

- [x] Sinh hai token ngẫu nhiên (`openssl rand -hex 32`), đặt `npx wrangler secret put PUBLISH_TOKEN` và `npx wrangler secret put CLIENT_TOKEN`. Lưu token ở nơi chủ dự án chọn (trình quản lý mật khẩu), không lưu trong repo.
- [x] `npx wrangler deploy` từ `crates/worker`. Ghi dòng dung lượng tổng và gzip.
- [x] `npx wrangler secret delete SPIKE_TOKEN`.

### Script nghiệm thu

- [x] `scripts/acceptance-server.sh <worker-url>`, đọc `PUBLISH_TOKEN`, `CLIENT_TOKEN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` từ môi trường; header token đi qua file tạm `chmod 600` như `measure-worker.sh`. Mỗi tiêu chí in `PASS` hoặc `FAIL` kèm lý do; thoát 1 nếu có `FAIL`. Dùng một `run_id` theo thời gian để dữ liệu thử không đụng nhau.
  1. Lấy `seq` từ `GET /items`; `cargo run -q -p cli -- publish ...` với `OS_WIDGET_SERVER` trỏ vào Worker; `GET /events?since=<seq>` có `item.created` với `item.id` bằng id CLI in ra.
  2. `POST /items` thiếu `title` → 400 và `message` chứa `title`; `vocab` thiếu `definition` → 400 và `field` là `body.meanings[0]`; `kind: "weather"` → 400 và `field` là `kind`.
  3. Publish hai lần cùng `dedupe_key` → cùng `id`, lần đầu 201, lần hai 200; `GET /events?since=<seq>` chỉ có một `item.created` cho id đó.
  4. `PATCH {"read":true}` → 204 và có `item.read`; gửi lại → 204 và không thêm sự kiện; `PATCH {"read":false}` → `item.unread`; `DELETE` → 204 và `item.deleted`; `DELETE` lại → 204, không thêm sự kiện; `PATCH` sau khi xoá → 404.
  5. Không header → 401; token client gọi `POST /items` → 403; token publish gọi `GET /events` → 403; token sai → 401.
  6. `GET $SUPABASE_URL/rest/v1/events?limit=1` với khoá anon → 200 và là mảng; `GET .../rest/v1/items?limit=1` với khoá anon → không trả về dòng nào (lỗi quyền 401/403, hoặc mảng rỗng đều tính là đạt, kèm ghi mã trạng thái); `POST .../rest/v1/rpc/purge_old_rows` với khoá anon → bị từ chối.
  - Thêm: `GET /events?since=0&limit=500` trả tối đa 100 sự kiện; `limit=0` → 400.
  - Cuối script: `DELETE` các mục đã tạo.
  - Thêm: một mục publish không có `ttl` có `expires_at` cách `created_at` 7 ngày (sai số vài giây).
- [x] Chạy script trên bản deploy; lưu đầu ra vào `plans/261123-0159-m1-server/reports/acceptance.md` (không có token).
- [x] Chạy `scripts/measure-worker.sh` với một lượng nhỏ (`count` 10) chỉ để chắc script còn chạy; không cần phân tích CPU.

### Tài liệu

- [x] `docs/architecture.md`:
  - §3.1: `ttl` mặc định 7 ngày (bỏ chữ "tạm đặt 30 ngày, chờ xác nhận").
  - §3.2: trường bắt buộc và tuỳ chọn của `vocab`; quy tắc URL của `image`, `link`, `audio_url`.
  - §4.1: hai token và 401/403; định dạng lỗi `{error, field, message}`; 201/200 của `POST /items`; dạng `{seq, items}` của `GET /items`; `limit` của `GET /events`; body `PATCH`; 204/404 của `PATCH`, `DELETE` và việc client coi 404 là xong.
  - §4.2: crate `cli` đã có, binary `os-widget`, hàm `envelope::parse`.
  - §4.3: quyền hai lớp cho anon; `purge_old_rows` qua `pg_cron`, thời gian giữ 30 ngày và lý do; `item: null` khi mục đã bị xoá hẳn.
  - §5: máy ngoại tuyến quá thời gian giữ dựa vào đối chiếu `GET /items`.
  - Dòng "Cập nhật" và "Trạng thái" ở đầu file.
- [x] `docs/roadmap.md`: thêm mục "Kết quả" cho Giai đoạn 1 với từng tiêu chí và đường dẫn tới báo cáo nghiệm thu; chuyển câu 2 của mục "Việc cần quyết định" sang "Đã chốt": `ttl` mặc định 7 ngày.
- [x] `docs/prd.md` §11 câu 3: ghi đã chốt `ttl` mặc định 7 ngày (2026-11-23).

## Verification

- `scripts/acceptance-server.sh` in sáu `PASS` và thoát 0 trên bản deploy.
- `npx wrangler secret list` có `PUBLISH_TOKEN`, `CLIENT_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY`, không có `SPIKE_TOKEN`.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'` không có kết quả.
- Liên kết trong các file docs đã sửa trỏ đúng; mọi khẳng định mới trong docs khớp với mã và kết quả script.

## Risk Assessment

- Gỡ `SPIKE_TOKEN` trước khi deploy bản mới sẽ làm bản cũ lỗi 500: deploy trước, gỡ sau.
- Khoá anon kiểu cũ đã bị tắt trên project: dùng khoá publishable (`sb_publishable_...`) cho tiêu chí 6; ghi rõ loại khoá trong báo cáo.
- Script để lại dữ liệu thử nếu dừng giữa chừng: dữ liệu có `source` là `acceptance` và bị dọn theo `ttl` ngắn (đặt `ttl` 3600 cho mục thử).
