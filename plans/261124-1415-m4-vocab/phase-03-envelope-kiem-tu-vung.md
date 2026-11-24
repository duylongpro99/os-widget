---
phase: 3
title: "Envelope: kiểm một từ vựng"
status: completed
priority: P1
effort: "1.5h"
dependencies: []
---

# Phase 3: Envelope: kiểm một từ vựng

Server-only. Không chạm `apps/`.

## Goal

Crate `envelope` có một hàm công khai kiểm một body `vocab` đứng riêng, dùng chung cho `envelope::parse`, endpoint `POST /vocab/words` (Phase 4) và lệnh `ingest` (Phase 5), và áp đủ trường bắt buộc của architecture §3.2.

## Context

- `crates/envelope/src/parse.rs` hàm `check`: nhánh `Body::Vocab` kiểm `word` không rỗng, `audio_url` là `https://`, có ít nhất một nghĩa và mỗi `definition` không rỗng. Chưa kiểm `ipa` và `pos` không rỗng, dù architecture §3.2 ghi hai trường này bắt buộc.
- `EnvelopeError` có `field` và `message`; Worker trả hai trường này trong lỗi 400.
- Chưa bên gửi thật nào gửi `vocab`; script `scripts/acceptance-server.sh` gửi `vocab` thiếu `definition`, lỗi đó vẫn giữ `field` là `body.meanings[0]`.

## Files to Create / Modify

- Modify: `crates/envelope/src/vocab.rs` (hàm kiểm)
- Modify: `crates/envelope/src/parse.rs` (nhánh `Body::Vocab` gọi hàm mới với tiền tố `body.`)
- Modify: `crates/envelope/src/lib.rs` (re-export)
- Create: `crates/envelope/tests/vocab.rs`

## Thiết kế

- `pub fn parse_vocab(value: &serde_json::Value) -> Result<VocabBody, EnvelopeError>`: giải mã một body `vocab` từ JSON với đường dẫn trường như `parse` (dùng `serde_path_to_error` đã có), rồi gọi `check_vocab`.
- `pub fn check_vocab(body: &VocabBody, prefix: &str) -> Result<(), EnvelopeError>`: `word`, `ipa`, `pos` không rỗng hoặc chỉ khoảng trắng; `word` không chứa xuống dòng (vì thành `title`); `audio_url` là `https://`; ít nhất một nghĩa; mỗi `definition` không rỗng. `field` có dạng `<prefix>ipa`, `<prefix>meanings[0].definition`.
- `check` gọi `check_vocab(b, "body.")`, nên `envelope::parse` áp cùng quy tắc.
- Siết thêm (`ipa`, `pos` không rỗng; `word` một dòng) là thay đổi có chủ ý theo architecture §3.2; ghi vào architecture ở Phase 10.

## Tasks & Steps

- [x] Thêm hai hàm, re-export ở `lib.rs`.
- [x] Test trong `tests/vocab.rs`: body đủ trường hợp lệ; thiếu `ipa`; `ipa` chỉ có khoảng trắng; `pos` rỗng; `word` có `\n`; `meanings` rỗng; `definition` rỗng ở nghĩa thứ hai cho `field` là `meanings[1].definition`; `audio_url` `http://` bị từ chối; envelope `vocab` có `ipa` rỗng qua `envelope::parse` cho `field` là `body.ipa`.
- [x] Chạy test cũ của crate: test round-trip và test lỗi hiện có vẫn pass.

## Verification

- `cargo test -p envelope` pass.
- `cargo build -p envelope --target wasm32-unknown-unknown` thành công.
- `cargo clippy --workspace -- -D warnings` sạch.

## Risk Assessment

- Đổi thứ tự kiểm làm đổi `field` của lỗi mà `scripts/acceptance-server.sh` tiêu chí 2 dựa vào: thiếu `definition` là lỗi giải mã, xảy ra trước `check`, nên `field` vẫn là `body.meanings[0]`; test hiện có giữ điều này.

## Rollback

Revert commit của phase; không có dữ liệu nào phụ thuộc.
