# Báo cáo cook: Envelope kiểm một từ vựng

Nhánh `vocab-envelope-checks` (worktree `/Users/onedayin20902/personal/os-widget-wt/vocab-envelope-checks`), tách từ `main` tại `e93a2d5`. Chưa merge.

## Kết quả

Crate `envelope` có hàm công khai kiểm một body `vocab` đứng riêng, và `envelope::parse` dùng chung hàm đó. Quy tắc nay áp đủ trường bắt buộc của architecture §3.2.

| Commit | Nội dung |
|---|---|
| `3a215f9` | Thêm `parse_vocab` và `check_vocab` với quy tắc cũ (`word` không rỗng, `audio_url` là `https://`, ít nhất một nghĩa, `definition` không rỗng); nhánh `Body::Vocab` của `parse` gọi `check_vocab(b, "body.")`; 9 test trong `tests/vocab.rs` (trước khi cài, test không biên dịch). |
| `f9ac233` | Siết thêm: `ipa` và `pos` không rỗng hoặc chỉ khoảng trắng, `word` không chứa xuống dòng; 4 test mới, cả 4 fail trước khi sửa và pass sau đó. |

## API công khai thêm

```rust
pub fn parse_vocab(value: &serde_json::Value) -> Result<VocabBody, EnvelopeError>;
pub fn check_vocab(body: &VocabBody, prefix: &str) -> Result<(), EnvelopeError>;
```

Cả hai re-export ở `envelope::`. `parse_vocab` đặt tên trường không tiền tố (`ipa`, `meanings[1].definition`); lỗi giải mã như thiếu trường `ipa` có `field` rỗng và tên trường nằm trong `message`, giống `parse` với trường cấp gốc. Tên khớp đúng phase file.

## Kiểm tra

- `cargo test -p envelope`: 46 pass (33 cũ, 13 mới).
- `cargo test --workspace`: 105 pass, 0 fail (92 cũ cộng 13).
- `cargo clippy --workspace -- -D warnings`: sạch.
- `cargo build -p envelope --target wasm32-unknown-unknown`: thành công.
- Test cũ `vocab_missing_definition_points_at_the_meaning` vẫn pass: thiếu `definition` vẫn cho `field` là `body.meanings[0]`, nên tiêu chí 2 của `scripts/acceptance-server.sh` không đổi. Các body `vocab` trong test của worker, CLI và hai script nghiệm thu đều có `ipa` và `pos` không rỗng.
- Không có test flaky.

## Lệch so với phase file

Không có. Hai test thêm ngoài danh sách của phase (body thiếu trường tuỳ chọn vẫn hợp lệ; `check_vocab` gắn tiền tố vào `field`).

## Ghi chú cho phase sau

- Phase 10 ghi vào architecture §3.2 rằng `ipa`, `pos` không được rỗng và `word` phải một dòng.
- Phase 5 cần bỏ những từ mà Free Dictionary API không trả IPA, vì `check_vocab` từ chối `ipa` rỗng.
