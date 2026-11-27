---
phase: 7
title: "Deploy, đo CPU cron và nghiệm thu server"
status: completed
priority: P1
effort: "4h"
dependencies: [2, 4, 5, 6]
---

# Phase 7: Deploy, đo CPU cron và nghiệm thu server

Server-only. Không chạm `apps/`. Có bước live: các bước đánh dấu **[operator]** chỉ chạy sau khi supervisor hỏi và operator đồng ý.

## Goal

Đưa migration, endpoint và Cron Trigger lên bản live, đo CPU của các lần chạy cron, nạp bộ từ đầu tiên, và kiểm tiêu chí 2 đến 5 của roadmap Giai đoạn 4 bằng một script lặp lại được.

## Context

- Cách deploy và kiểm theo Phase 5 của M1 (`plans/261123-0159-m1-server/phase-05-deploy-va-nghiem-thu.md`): `supabase link --project-ref gykrhmpliphrcpiryzuq`, `supabase db push`, `npx wrangler deploy` từ `crates/worker`.
- Cách đo CPU theo M0 (`plans/261122-0754-m0-kiem-chung-worker-rust/reports/d-results.md`): `npx wrangler tail os-widget --format json`, mỗi sự kiện có `cpuTime` và `outcome`.
- Câu hỏi 1 đến 4 có thể đã đổi giá trị mặc định trong `settings`; dùng giá trị ghi ở mục "Operator answers" của `plan.md`.

## Files to Create / Modify

- Create: `scripts/acceptance-vocab.sh`
- Create: `plans/261124-1415-m4-vocab/reports/acceptance-server.md`

## Tasks & Steps

### Live, theo thứ tự

- [x] **[operator] G1. Migration.** Sao lưu trước: `supabase db dump --linked -f <ngoài repo>/before-vocab.sql`. Rồi `supabase db push`. Kiểm `select key, value from settings` có đủ sáu khoá; `anon` không đọc được `vocab_words` và `settings`. Bằng chứng: `reports/acceptance-server.md`, mục "G1: sao lưu và migration".
- [x] **[operator] G2. Deploy Worker có Cron Trigger.** `npx wrangler deploy` (sau G1, để cron không gọi RPC chưa tồn tại). Ghi dòng dung lượng tổng và gzip. `npx wrangler triggers` hoặc dashboard cho thấy `*/5 * * * *`. `scripts/acceptance-server.sh` vẫn pass. Bằng chứng: `reports/acceptance-server.md`, mục "G2: deploy Worker có Cron Trigger" (bản `bf216bba`, 684.06 KiB / gzip 224.20 KiB, `acceptance-server.sh` 8/8).
- [x] **[operator] G3. Nạp bộ từ đầu tiên.** `os-widget ingest words` với danh sách đã chốt ở câu hỏi 2, rồi `os-widget ingest book <sách> --origin "<tên>"` (xem `--dry-run` trước). Việc này bắt đầu gửi thẻ thật tới máy của operator theo chu kỳ. Bằng chứng: `reports/acceptance-server.md`, mục "G3: nạp bộ từ đầu tiên" (`stored 17, skipped 0`; sách `stored 45, skipped 5`).
- [x] **[operator] G4. Đổi `settings` trên live để kiểm** (tiêu chí 4): chạy bằng `psql` với chuỗi kết nối của project, không lưu chuỗi đó vào repo. Trả lại giá trị cũ sau khi kiểm. Bằng chứng: `reports/acceptance-server.md`, mục "Phần 3: chạy lại tiêu chí 4" (trả về giá trị cũ lúc 21:45:53).

### Đo CPU cron

- [x] Chạy `npx wrangler tail os-widget --format json > <scratch>/tail.jsonl` ít nhất 1 giờ sau G2 (khoảng 12 lần chạy). Lọc sự kiện có `event.cron`; ghi số lần chạy, `cpuTime` p50 và lớn nhất, số `outcome` khác `ok` (đặc biệt `exceededCpu`), và số lần `vocab.tick status=sent` so với số lần tới hạn. Bằng chứng: `reports/acceptance-server.md`, mục "CPU của các lần chạy cron" (13 lần, p50 9 ms, lớn nhất 17 ms, 0 `exceededCpu`) và mục "CPU" của phần 2 (2 lần `sent`; 131/131 lần tới hạn đã gửi).
- [x] Đo luôn `POST /vocab/words` từ các request của G3 (`cpuTime` theo path). Bằng chứng: `reports/acceptance-server.md`, mục "CPU" của phần 2 (6 request, p50 7 ms, lớn nhất 28 ms).
- [ ] Nếu có lần chạy cron `exceededCpu` hoặc lần tới hạn không gửi: dừng, báo supervisor. Đường dự phòng **[operator] G5**: migration mới `select cron.schedule('os-widget-vocab', '*/5 * * * *', 'select public.vocab_tick()')`, xoá `[triggers]` khỏi `wrangler.toml` và deploy lại. `vocab_tick` không đổi. Không cần: không lần chạy nào `exceededCpu` và mọi lần tới hạn đều gửi.

### Script nghiệm thu

`scripts/acceptance-vocab.sh <worker-url>` đọc `PUBLISH_TOKEN`, `CLIENT_TOKEN` từ môi trường, header qua file tạm `chmod 600` như `scripts/acceptance-server.sh`, in `PASS`/`FAIL` mỗi tiêu chí, thoát 1 nếu có `FAIL`:

- [x] **Tiêu chí 2.** `os-widget ingest words` với 3 từ đủ trường (ví dụ `serendipity`, `meticulous`, `garrulous`) và 1 từ thiếu IPA (`vindicate`): đầu ra có `stored 3, skipped 1`. Chạy lại: vẫn `stored 3` và số dòng không tăng (kiểm qua `psql` khi có `SUPABASE_DB_URL`, nếu không thì qua phản hồi và ghi rõ trong báo cáo). Body gửi đi qua `envelope::check_vocab`, nên "đủ trường" được chứng minh bởi `stored`. Bằng chứng: `reports/acceptance-server.md`, mục "Tiêu chí 2 và 3" (PASS, 62 dòng trước và sau lần chạy lại).
- [x] **Tiêu chí 3.** `os-widget ingest book crates/cli/tests/fixtures/book/sample.txt --origin acceptance-book --max 3`: mọi từ `origin = 'acceptance-book'` có `context` là một câu có trong file. Bằng chứng: `reports/acceptance-server.md`, mục "Tiêu chí 2 và 3" (PASS).
- [x] **Tiêu chí 4** (cần `SUPABASE_DB_URL`, bước G4). Ghi `vocab_interval_minutes` cũ; đặt 5; theo dõi `GET /events` trong 15 phút: có ít nhất 2 `item.created` của mục `source = 'vocab-cron'` cách nhau khoảng 5 phút; đặt 15 và theo dõi 20 phút: khoảng cách giữa hai mục kế tiếp ≥ 14 phút. Trả lại giá trị cũ. Không deploy giữa chừng. Bằng chứng: `reports/acceptance-server.md`, mục "Phần 3: chạy lại tiêu chí 4" (PASS: 300 và 301 giây ở 5 phút, 899 giây ở 15 phút).
- [x] **Tiêu chí 5.** Kiểm đầy đủ trên Supabase cục bộ bằng `supabase test db` (test của Phase 2: `stop` không tạo mục, `rotate` gửi tiếp). Trên live chỉ kiểm đọc: `settings.vocab_when_exhausted` có giá trị đã chốt. Không làm cạn bộ từ thật để kiểm. Bằng chứng: `reports/acceptance-server.md`, mục "`scripts/acceptance-vocab.sh`" (PASS, pgTAP 69 test) và "Bằng chứng live thêm cho tiêu chí 5 (quay vòng)".
- [x] Mục thử dùng `origin` bắt đầu bằng `acceptance`; cuối script không xoá từ (chúng là từ thật và hữu ích), chỉ ghi lại tên. Bằng chứng: `reports/acceptance-server.md`, mục "Trạng thái live khi kết thúc" của phần 2 (`acceptance-words` 3, `acceptance-book` 1).
- [x] Lưu đầu ra script và số đo CPU vào `reports/acceptance-server.md` (không có token, không có chuỗi kết nối). Bằng chứng: `reports/acceptance-server.md`; quét secret trên diff không có kết quả.

## Verification

- `scripts/acceptance-vocab.sh` in `PASS` cho tiêu chí 2, 3, 4, 5 và thoát 0.
- `scripts/acceptance-server.sh` vẫn pass trên bản deploy.
- `reports/acceptance-server.md` có số lần chạy cron, `cpuTime` p50 và lớn nhất, số `exceededCpu`.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}|postgres(ql)?://' -- ':!.claude'` không có kết quả.

## Risk Assessment

- Lần chạy cron rơi vào isolate lạnh vượt 10 ms: đã có đường G5 không cần sửa logic; đánh đổi là `pg_cron` có thể không giữ project Supabase hoạt động như request PostgREST từ Worker.
- Kiểm tiêu chí 4 làm gửi nhiều thẻ trong 35 phút: báo operator trước (G4), hoặc tạm đặt `vocab_priority` thành `low` trong lúc kiểm để không bật popup.
- Deploy trước migration làm cron lỗi 404 mỗi 5 phút: thứ tự G1 rồi G2.

## Rollback

- Tắt gửi ngay, không deploy: `update settings set value = 'false' where key = 'vocab_enabled'`.
- Gỡ Cron Trigger: xoá `[triggers]` và `npx wrangler deploy`.
- Gỡ schema: migration mới xoá hai hàm và hai bảng; bản dump ở G1 để khôi phục nếu cần.
