---
phase: 5
title: "CLI ingest words từ Free Dictionary API"
status: pending
priority: P1
effort: "4h"
dependencies: [1, 3]
---

# Phase 5: CLI `ingest words` từ Free Dictionary API

Server-only. Không chạm `apps/`. Không ghi vào project live ở phase này.

## Goal

Lệnh `os-widget ingest words <PATH|->` đọc một danh sách từ, tra từng từ ở Free Dictionary API, ánh xạ sang `VocabBody`, bỏ từ thiếu trường bắt buộc, và gửi các từ hợp lệ theo lô tới `POST /vocab/words`.

## Context

- CLI ở `crates/cli/src/main.rs`: `clap` với `Command::Publish`, `ureq` 3, `OS_WIDGET_SERVER` hoặc `--server`, token chỉ từ `OS_WIDGET_PUBLISH_TOKEN`, mã thoát 2 khi dữ liệu sai và 1 với lỗi khác (`EXIT_INVALID`, `EXIT_FAILURE`).
- Độ phủ và hình dạng JSON của API: `plans/261124-1415-m4-vocab/reports/api-coverage.md` và 20 file trong `reports/api-samples/`.
- Hàm kiểm `envelope::check_vocab` (Phase 3); endpoint và giới hạn 50 từ mỗi lô (Phase 4).

## Files to Create / Modify

- Modify: `crates/cli/src/main.rs` (thêm `Command::Ingest` với lệnh con `words`; giữ `publish` như cũ)
- Create: `crates/cli/src/ingest/mod.rs` (lệnh con, gửi lô, báo cáo)
- Create: `crates/cli/src/ingest/dictionary.rs` (gọi API, ánh xạ thuần)
- Create: `crates/cli/tests/fixtures/dictionary/*.json` (chép từ `reports/api-samples/`, ít nhất `serendipity`, `candid`, `resilient`, `wandered`, `benevolent`)
- Modify: `crates/cli/Cargo.toml` chỉ khi cần thêm phụ thuộc (ưu tiên không thêm)

## Thiết kế

**Đầu vào.** Mỗi dòng một từ; bỏ dòng trống và dòng bắt đầu bằng `#`; chuẩn hoá `lower(trim)`; bỏ trùng trong cùng file; bỏ từ có ký tự ngoài chữ cái, dấu nháy đơn và gạch nối.

**Ánh xạ** (`fn map_entry(word: &str, json: &Value) -> Result<VocabBody, SkipReason>`, thuần, test bằng fixture):

| Trường | Quy tắc |
|---|---|
| `word` | Từ đã chuẩn hoá ở đầu vào. |
| `ipa` | `phonetic` của entry đầu tiên khác rỗng; nếu không có, `text` khác rỗng đầu tiên trong mọi `phonetics[]`. Không có → bỏ, lý do `missing ipa`. |
| `pos` | `partOfSpeech` của nhóm nghĩa có nhiều định nghĩa nhất trên mọi entry; bằng nhau thì nhóm đứng trước. |
| `meanings` | Tối đa 3 định nghĩa của nhóm đó; `examples` là `[example]` khi có. Không có định nghĩa → bỏ. |
| `synonyms`, `antonyms` | Của nhóm đã chọn (cấp nhóm rồi cấp định nghĩa), rồi tới các nhóm khác; bỏ trùng, giữ thứ tự, tối đa 6. |
| `audio_url` | `audio` khác rỗng đầu tiên, ưu tiên file `-us.mp3`; `//` ở đầu đổi thành `https://`; không phải `https://` thì bỏ trường (không bỏ từ). |
| `context` | Không đặt (API không có). |

Kết quả cuối qua `envelope::check_vocab`; lỗi → bỏ với lý do là `field`.

**Gọi API.** `GET {dictionary_url}/{word}` với `dictionary_url` mặc định `https://api.dictionaryapi.dev/api/v2/entries/en` (cờ `--dictionary-url` để trỏ vào máy chủ thử). Tuần tự, cách nhau ít nhất 300 ms; 404 → bỏ với lý do `not found`; 429 và 5xx thử lại tối đa 3 lần, chờ 1, 2, 4 giây; vẫn lỗi → bỏ với lý do `dictionary error <status>`. User-Agent `os-widget-ingest`.

**Gửi.** Lô 25 từ tới `POST /vocab/words` với `origin` mặc định `dictionaryapi.dev` (cờ `--origin`). Lỗi 400 từ server → in `field`, `message`, thoát 2; 401, 403, 5xx, lỗi mạng → thoát 1. Lô đã gửi trước đó vẫn được giữ (nạp lại là an toàn vì upsert).

**Báo cáo.** Mỗi từ một dòng `ok <word>` hoặc `skip <word> <lý do>` ra stderr; cuối cùng `stored <n>, skipped <m>` ra stdout. `--dry-run` tra API và in JSON các body sẽ gửi, không gọi server và không cần token.

## Tasks & Steps

- [ ] Thêm `Command::Ingest(IngestArgs)` với lệnh con `Words { path, origin, dictionary_url, server, dry_run }`.
- [ ] `dictionary.rs`: `map_entry` và hàm tra có thử lại; tách đồng hồ chờ để test không ngủ thật.
- [ ] `mod.rs`: đọc danh sách, gọi tra, chia lô, gửi, báo cáo.
- [ ] Unit test với fixture:
  - `serendipity` → đủ trường, `audio_url` `https://`;
  - `candid` → `pos` là `adjective` (nhóm 3 định nghĩa), không phải `noun`;
  - `resilient` → bỏ, `missing ipa`;
  - `wandered` → có `examples` và `synonyms`;
  - danh sách có dòng trống, `#`, chữ hoa, từ lặp → đúng các từ đã chuẩn hoá;
  - phản hồi server 200 `{"stored":n}`, 400 có `field`, 401 → đúng mã thoát.
- [ ] Thử cục bộ với Worker `wrangler dev` và Supabase cục bộ (như Phase 4): `ingest words` với 5 từ mẫu, nạp lại lần hai, `select count(*) from vocab_words` không đổi. Lần thử này gọi API thật tối đa 10 request.

## Verification

- `cargo test -p cli` pass.
- `cargo clippy --workspace -- -D warnings` sạch.
- `os-widget ingest words --dry-run <file 5 từ>` in 4 body (1 từ thiếu IPA bị bỏ) khi danh sách gồm `serendipity`, `candid`, `resilient`, `wandered`, `benevolent`.
- Vòng thử cục bộ: lần hai không tăng số dòng.

## Risk Assessment

- API bị giới hạn tần suất khi nạp danh sách dài: tuần tự 300 ms, thử lại có chờ; danh sách vài trăm từ mất vài phút, chấp nhận được với việc chạy tay.
- Định dạng API đổi: ánh xạ trả lý do bỏ thay vì panic; số từ bị bỏ tăng đột ngột là dấu hiệu.
- Token lộ qua cờ: như `publish`, token chỉ từ biến môi trường.

## Rollback

Revert commit; chưa ghi dữ liệu live.
