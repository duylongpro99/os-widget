---
phase: 2
title: "Envelope ba loại và lỗi nêu rõ trường"
status: pending
priority: P1
effort: "3h"
dependencies: []
---

# Phase 2: Envelope ba loại và lỗi nêu rõ trường

## Goal

Crate `envelope` có đủ ba loại `notification`, `vocab`, `generic` theo architecture §3.2, và một hàm parse duy nhất trả về lỗi nêu đường dẫn tới trường sai, dùng chung cho Worker và CLI.

## Files to Create / Modify

- Modify: `crates/envelope/Cargo.toml` (thêm `serde_json`, `serde_path_to_error` vào `[dependencies]`)
- Modify: `crates/envelope/src/lib.rs`
- Có thể tách: `crates/envelope/src/vocab.rs`, `crates/envelope/src/generic.rs` nếu `lib.rs` vượt khoảng 300 dòng.

## Thiết kế đã chốt

**Kiểu dữ liệu.** Giữ `Envelope` và `Body` như M0 (cặp `kind`/`body` gắn thẻ kề nhau, flatten vào envelope) để định dạng JSON và các test round-trip không đổi. Thêm hai biến thể:

- `Vocab(VocabBody)`: `word`, `ipa`, `pos`, `meanings: Vec<Meaning>` (mỗi `Meaning` có `definition` và `examples: Vec<String>` mặc định rỗng) là bắt buộc; `audio_url`, `context` là `Option`; `synonyms`, `antonyms` mặc định rỗng. `body` bắt buộc với `vocab`.
- `Generic(GenericBody)`: `blocks: Vec<Block>`, `Block` là enum gắn thẻ nội bộ theo `type` với bảy loại ở §3.2 (`heading`, `text`, `fields`, `list`, `image`, `code`, `link`). `list.ordered` mặc định `false`; `code.language` và `image.alt` là `Option`. Block lạ bị từ chối ở server (client mới là bên bỏ qua block lạ, §3.3).

Không dùng `deny_unknown_fields`: theo §3.3, thêm trường tuỳ chọn không tăng `v`, nên bên gửi mới hơn server không bị chặn.

**Parse hai bước.** `serde(flatten)` làm mất đường dẫn lỗi bên trong `body`, nên thêm:

```rust
pub fn parse(bytes: &[u8]) -> Result<Envelope, EnvelopeError>
pub struct EnvelopeError { pub field: String, pub message: String }
```

1. Deserialize vào một struct thô có `kind: String`, `body: Option<serde_json::Value>` và các trường chung, qua `serde_path_to_error`, để lỗi trường chung có đường dẫn (`title`, `ttl`…).
2. Chọn kiểu `body` theo `kind`; `kind` lạ cho `field = "kind"`, `message = "unknown kind \`weather\`, expected one of notification, vocab, generic"`. Deserialize `body` qua `serde_path_to_error` và thêm tiền tố `body.` vào đường dẫn (ví dụ `body.meanings[0].definition`).
3. Kiểm ngữ nghĩa, mỗi lỗi đặt `field` cụ thể:
   - `v` phải bằng 1.
   - `source`, `title`, `summary` không rỗng sau khi bỏ khoảng trắng; `title` không chứa xuống dòng.
   - `url` (nếu có), `link.url` bắt đầu bằng `http://` hoặc `https://`; `image.url` bắt đầu bằng `https://` (architecture §7); `audio_url` bắt đầu bằng `https://`.
   - `ttl` (nếu có) ≥ 1; `dedupe_key` (nếu có) không rỗng.
   - `vocab`: `word` không rỗng, `meanings` có ít nhất một mục, mỗi `definition` không rỗng.

Khi serde báo thiếu trường, đường dẫn trỏ tới đối tượng cha và thông báo nêu tên trường (`missing field \`title\``); giữ nguyên thông báo đó. Bỏ phần "at line X column Y" khỏi `message`.

`Display` của `EnvelopeError` là `"{field}: {message}"` (hoặc chỉ `message` khi `field` rỗng, tức lỗi JSON ở gốc).

## Tasks & Steps

- [ ] Thêm các kiểu `VocabBody`, `Meaning`, `GenericBody`, `Block` và hai biến thể của `Body`; cập nhật `Body::kind()`.
- [ ] Viết `parse` và `EnvelopeError` theo thiết kế; giữ `Deserialize` của `Envelope` để test cũ còn chạy.
- [ ] Test, mỗi trường hợp một hàm:
  - `vocab` đúng ví dụ ở §3.2 parse được và round-trip không đổi.
  - `generic` có đủ bảy block parse được và round-trip không đổi.
  - Thiếu `title` → `field` là `""` hoặc gốc, `message` chứa `title`.
  - `kind` lạ → `field == "kind"`.
  - `vocab` thiếu `definition` → `field == "body.meanings[0]"`, `message` chứa `definition`.
  - `generic` có block `type: "video"` → `field` bắt đầu bằng `body.blocks[0]`.
  - `v: 2`, `title` có `\n`, `url: "javascript:x"`, `image.url` dạng `http://`, `ttl: 0`, `meanings: []` → mỗi cái một lỗi với đúng `field`.
  - JSON hỏng (`{`) → lỗi, không panic.
- [ ] Các test M0 hiện có vẫn pass.

## Verification

- `cargo test -p envelope` pass.
- `cargo build -p envelope --target wasm32-unknown-unknown --release` thành công.
- `cargo clippy -p envelope -- -D warnings` sạch.

## Risk Assessment

- `serde_path_to_error` với enum gắn thẻ nội bộ (`Block`) có thể chỉ trỏ tới `body.blocks[0]` mà không sâu hơn: chấp nhận, vì thông báo của serde vẫn nêu tên trường hoặc biến thể sai.
- Thêm `serde_json` làm dependency thường làm Worker to thêm một chút: Worker đã phụ thuộc `serde_json`, nên dung lượng gần như không đổi.
