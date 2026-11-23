---
phase: 4
title: "CLI publish"
status: completed
priority: P1
effort: "2h"
dependencies: [2]
---

# Phase 4: CLI publish

## Goal

Crate `cli` với binary `os-widget` có lệnh `publish` cho agent và cron: validate envelope bằng `envelope::parse` trước khi gửi, rồi gọi `POST /items` bằng token publish.

## Files to Create / Modify

- Create: `crates/cli/Cargo.toml`, `crates/cli/src/main.rs`
- Modify: `Cargo.toml` (thêm `crates/cli` vào `members`)

## Thiết kế đã chốt

**Dependency.** `envelope`, `serde_json`, `clap` (derive), `ureq` 3 (TLS rustls mặc định). Chọn `ureq` vì CLI chỉ cần một request đồng bộ; không cần runtime async. Crate này chỉ build cho máy thật.

**Cấu hình.** `OS_WIDGET_SERVER` (URL Worker) và `OS_WIDGET_PUBLISH_TOKEN`. Cờ `--server` ghi đè biến môi trường. Token chỉ lấy từ biến môi trường để không lộ trong danh sách tiến trình.

**Hai cách đưa nội dung.**

- Envelope đầy đủ: `os-widget publish --file envelope.json`, hoặc `--file -` để đọc từ stdin. Dùng cho `vocab`, `generic` và mọi bên gửi đã tự dựng JSON.
- Cờ cho `notification`, trường hợp phổ biến nhất (S1, S3): `os-widget publish --source blog-agents --title "..." --summary "..." [--text "..."] [--link URL] [--priority low|normal|high] [--ttl SECS] [--dedupe-key KEY]`. CLI dựng JSON envelope rồi đi qua cùng `envelope::parse` như cách trên. Dùng `--link` thay vì `--url` để không lẫn với `--server`.

`--file` và nhóm cờ `notification` loại trừ nhau (clap `conflicts_with`).

**`--dry-run`.** Chỉ validate và in envelope đã chuẩn hoá ra stdout, không gọi mạng.

**Đầu ra và mã thoát.**

| Kết quả | stdout | stderr | Mã thoát |
|---|---|---|---|
| Tạo mới (201) | `id` | | 0 |
| Đã có theo `dedupe_key` (200) | `id` | `duplicate: existing item returned` | 0 |
| Validate cục bộ lỗi | | `invalid envelope: <field>: <message>` | 2 |
| Server trả 400 | | `invalid envelope: <field>: <message>` từ JSON lỗi | 2 |
| 401, 403, 5xx, lỗi mạng, thiếu cấu hình | | mô tả lỗi kèm mã HTTP nếu có | 1 |

## Tasks & Steps

- [x] Tạo crate, thêm vào workspace; `cargo build -p cli` không kéo `worker` vào.
- [x] Viết `publish` theo thiết kế; tách hàm thuần "dựng envelope từ cờ" và "đổi phản hồi HTTP thành kết quả" để test.
- [x] Unit test: cờ tối thiểu dựng ra envelope hợp lệ; `--priority urgent` bị clap từ chối; `--text` vào `body.text`; phản hồi 201, 200, 400 có `field`, 401 đổi đúng thành mã thoát.
- [x] Kiểm thủ công `--dry-run` với một file `vocab` hợp lệ và một file thiếu `definition`.

## Verification

- `cargo test -p cli` pass.
- `cargo clippy -p cli -- -D warnings` sạch.
- `cargo run -p cli -- publish --dry-run --file <vocab hỏng>` thoát mã 2 và in `body.meanings[0]`.
- Gọi thật vào Worker (sau Phase 3 deploy hoặc `wrangler dev`) ở Phase 5.

> Ghi chú (2026-11-23): mọi mục ở trên đã đạt khi merge vào `main`. Riêng việc gọi thật vào Worker chưa làm ở phase này; Phase 5 kiểm nó qua tiêu chí 1 của `scripts/acceptance-server.sh`.

## Risk Assessment

- `ureq` 3 đổi API so với bản 2: theo tài liệu của bản đang khoá trong `Cargo.lock`, không chép ví dụ cũ.
- `--file -` khi stdin là terminal sẽ chờ mãi: chấp nhận, như các CLI Unix khác.
