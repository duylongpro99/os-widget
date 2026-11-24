# Review: Envelope kiểm một từ vựng

Nhánh `vocab-envelope-checks` (head `7634cbc`, tách từ `main` tại `e93a2d5`) đạt yêu cầu và đã merge vào `main` bằng `--no-ff` tại `c08718c`. Không có lỗi cần sửa, nên không có commit sửa nào.

## Đối chiếu với phase file và architecture §3.2

- `check_vocab` kiểm `word`, `ipa`, `pos` không rỗng hoặc chỉ khoảng trắng; `word` không chứa `\n` hoặc `\r`; `audio_url` là `https://`; ít nhất một nghĩa; mỗi `definition` không rỗng. Khớp phase file và danh sách trường bắt buộc ở architecture §3.2.
- `field` đúng khi có và không có tiền tố: `parse_vocab` cho `ipa`, `meanings[1].definition`; `envelope::parse` gọi `check_vocab(b, "body.")` và cho `body.ipa`, `body.meanings[0].definition`. Lỗi giải mã (thiếu trường) dùng `path_error`, nên thiếu `definition` vẫn là `body.meanings[0]` qua `parse` và `meanings[1]` qua `parse_vocab`.
- API công khai `parse_vocab` và `check_vocab` được re-export ở `envelope::`. Ba helper trong `parse.rs` chỉ nâng lên `pub(crate)`, không lộ ra ngoài crate.

## Thay đổi hợp đồng

Quy tắc mới (`ipa`, `pos` không rỗng, `word` một dòng) không từ chối body nào mà các bên gửi hiện có đang dùng:

| Nơi gửi `vocab` | `ipa` / `pos` | Kết quả |
|---|---|---|
| `scripts/acceptance-server.sh` tiêu chí 2 | `/w/` / `noun`, thiếu `definition` | Vẫn 400 với `field` `body.meanings[0]` (lỗi giải mã đứng trước `check_vocab`) |
| `scripts/acceptance-menu-bar.sh` tiêu chí 6 | IPA đầy đủ / `noun` | Vẫn hợp lệ |
| `crates/cli/src/main.rs` test lỗi cục bộ | `/w/` / `noun` | Vẫn `body.meanings[0]: missing field \`definition\`` |
| `crates/worker/src/items.rs` test 400 | `i` / `n` | Vẫn `body.meanings[0]` |
| `crates/envelope/tests/parse.rs` | IPA đầy đủ / `noun` | Pass |

Worker đang deploy vẫn dùng quy tắc cũ cho tới bước deploy của Phase 7; không có bên gửi thật nào gửi `vocab` trước đó, nên khoảng lệch này không ảnh hưởng.

## Kiểm tra

- Mutation: xoá dòng kiểm `ipa` trong `check_vocab` làm 2 test fail (`whitespace_ipa_is_rejected`, `envelope_with_empty_ipa_names_the_body_field`); đã revert, cây sạch.
- Trên nhánh, sau khi merge `main` vào (`68536c9`, `main` đã có widget target của M3, không trùng file): `cargo test --workspace` 105 pass, `cargo clippy --workspace -- -D warnings` sạch, `cargo build -p envelope --target wasm32-unknown-unknown` thành công.
- Trên `main` sau merge: `cargo test --workspace` 105 pass, `swift test` 127 pass.

## Ghi chú cho phase sau

- Phase 5 phải bỏ từ mà Free Dictionary API không trả IPA hoặc từ loại, vì `check_vocab` từ chối chúng (cook report đã nêu).
- Phase 10 ghi vào architecture §3.2 rằng `ipa`, `pos` không được rỗng và `word` phải một dòng.
