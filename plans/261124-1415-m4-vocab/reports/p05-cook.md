# Báo cáo cook: CLI `ingest words` từ Free Dictionary API

Nhánh `vocab-ingest-words` (worktree `/Users/onedayin20902/personal/os-widget-wt/vocab-ingest-words`), tách từ `main` tại `bd14774`. Chưa merge.

## Kết quả

`os-widget ingest words <PATH|->` đọc danh sách từ, tra từng từ ở Free Dictionary API, ánh xạ sang `VocabBody`, kiểm bằng `envelope::check_vocab`, bỏ từ không đủ trường và gửi các từ hợp lệ theo lô 25 tới `POST /vocab/words`. Phần Worker (phase 4) chưa có, nên client được test với máy chủ giả cục bộ theo đúng hợp đồng trong phase 4.

| Commit | Nội dung |
|---|---|
| `d33b64e` | `ingest/dictionary.rs`: `map_entry` thuần, `Dictionary::lookup` có giãn cách 300 ms và thử lại 1, 2, 4 giây (transport và đồng hồ truyền vào); 6 fixture thật; 25 test. |
| `c60dbde` | Tách `http()` và `http_fetch()` để test dùng transport thật với đồng hồ rỗng. |
| `afc5d7d` | `ingest/mod.rs` và `main.rs`: đọc danh sách, chia lô, gửi, báo cáo, mã thoát; 18 test mới ở `mod.rs`, 3 test cờ ở `main.rs`. |

## Cờ thêm

`os-widget ingest words <PATH|-> [--origin NAME=dictionaryapi.dev] [--dictionary-url URL] [--server URL] [--dry-run]`. Token vẫn chỉ từ `OS_WIDGET_PUBLISH_TOKEN`; `--dry-run` không cần token và không cần server.

## Kiểm tra

- `cargo test -p cli`: 69 pass (trước 23), chạy 3 lần đều pass, không có test chập chờn.
- `cargo test --workspace`: 151 pass (trước 105).
- `cargo clippy --workspace -- -D warnings`: sạch.
- Quy tắc ánh xạ có test fail trước khi cài (16 fail với bản giả; 17 fail ở `mod.rs`); riêng phần thử lại, giãn cách và mã trạng thái của `lookup` được viết cùng lúc với bản cài nên không có lần chạy đỏ riêng.
- Thử tay (chỉ 5 GET chỉ đọc tới `api.dictionaryapi.dev`): `ingest words --dry-run` với `serendipity, candid, resilient, wandered, benevolent` in 4 body (`serendipity` noun, `candid` adjective 3 nghĩa, `wandered` verb, `benevolent` adjective không có audio), bỏ `resilient` với `missing ipa`; stderr cuối `dry run: would store 4, skipped 1`.
- Không có tiến trình nào còn chạy; test dùng máy chủ giả trên cổng ngẫu nhiên và dừng khi test xong.

## Khác với phase file

- Dry-run in mảng JSON (pretty) ra stdout và dòng tóm tắt `dry run: would store n, skipped m` ra stderr, để stdout luôn là JSON hợp lệ; chạy thật in `stored n, skipped m` ra stdout như phase.
- Dòng không phải từ (có khoảng trắng, chữ số, dấu chấm...) không bị bỏ lặng lẽ mà báo `skip <dòng> invalid characters`; tính vào `skipped`.
- Lý do bỏ do `check_vocab` báo có dạng `invalid <field>: <message>`; thêm lý do `no definition` và `unexpected dictionary response`.
- Lỗi mạng khi tra API không thử lại (phase chỉ yêu cầu 429 và 5xx): bỏ từ với `dictionary error: <lý do>`.
- Lô lỗi giữa chừng dừng chạy, in `stored n, skipped m` của phần đã gửi ra stdout cùng thông báo lỗi và mã thoát 2 hoặc 1.
- `origin` rỗng hoặc dài hơn 200 ký tự bị từ chối cục bộ với mã 2 (cùng giới hạn của endpoint).
- Chưa chạy vòng thử cục bộ với `wrangler dev` và Supabase (nhiệm vụ cuối của phase): endpoint phase 4 chưa tồn tại và brief cấm gọi Worker thật. Bước "nạp lại lần hai không tăng số dòng" thuộc về phase 4 và 7; ở đây chỉ kiểm được client gửi cùng nội dung hai lần như nhau.

## Chưa giải quyết

- Vòng thử cục bộ nói trên cần chạy khi phase 2 và 4 đã merge (nên gộp vào bước nghiệm thu ở phase 7).
- Body gửi đi có `"context": null` cho mọi từ; Worker phase 4 cần chấp nhận `null` (serde `Option` mặc định chấp nhận).
