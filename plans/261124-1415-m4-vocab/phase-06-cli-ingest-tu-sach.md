---
phase: 6
title: "CLI ingest book từ sách .txt"
status: completed
priority: P1
effort: "4h"
dependencies: [5]
---

# Phase 6: CLI `ingest book` từ sách `.txt`

Server-only. Không chạm `apps/`. Không ghi vào project live ở phase này.

## Goal

Lệnh `os-widget ingest book <PATH> --origin <tên sách>` đọc một sách văn bản thuần UTF-8, chọn các từ đáng học, gắn cho mỗi từ một câu ngữ cảnh lấy từ sách, bổ sung phần còn lại bằng API từ điển của Phase 5 và gửi lên `POST /vocab/words`.

## Context

- Architecture §4.4: "Sách cung cấp từ và câu ngữ cảnh; API từ điển bổ sung phần còn thiếu. Từ nào không bổ sung đủ trường bắt buộc thì không được nạp."
- Quyết định D4: chỉ `.txt`; EPUB để sau.
- Lần đo ở Phase 1: dạng biến tố (`wandered`, `lanterns`) tra được trực tiếp, nên không cần đưa về dạng gốc.

## Files to Create / Modify

- Create: `crates/cli/src/ingest/book.rs` (tách câu, tách từ, chọn từ, lấy ngữ cảnh; thuần)
- Create: `crates/cli/src/ingest/stopwords.rs` (danh sách từ chức năng tiếng Anh viết tay, khoảng 150 từ)
- Modify: `crates/cli/src/ingest/mod.rs` (lệnh con `book`, dùng lại tra từ và gửi lô của Phase 5)
- Create: `crates/cli/tests/fixtures/book/sample.txt` (vài đoạn văn tự viết, có đầu và cuối kiểu Project Gutenberg)

## Thiết kế

**Đọc.** File UTF-8; lỗi mã hoá → thoát 2 với thông báo. Nếu có dòng `*** START OF` và `*** END OF` (Project Gutenberg) thì chỉ lấy phần giữa. Nối từ bị ngắt dòng bằng gạch nối (`-\n`), đổi nháy cong thành nháy thẳng, gộp khoảng trắng.

**Câu.** Tách tại `.`, `!`, `?` theo sau là khoảng trắng, và tại dòng trống. Câu ngắn hơn 20 ký tự bị bỏ khỏi vai trò ngữ cảnh.

**Từ ứng viên.** Token là dãy chữ cái ASCII; bỏ token có dấu nháy. Một từ (viết thường) là ứng viên khi: dài ít nhất `--min-length` (mặc định 5); không nằm trong `stopwords.rs`; không nằm trong 300 từ xuất hiện nhiều nhất của chính cuốn sách (từ quá phổ biến); có ít nhất một lần xuất hiện viết thường (loại tên riêng); xuất hiện ít nhất 2 lần. Xếp theo lần xuất hiện đầu tiên; lấy tối đa `--max` (mặc định 50, theo câu hỏi 2).

**Ngữ cảnh.** Câu đầu tiên chứa từ ở dạng viết thường. Dài hơn 240 ký tự thì cắt quanh từ, thêm `…` ở đầu hoặc cuối bị cắt. Đặt vào `context` của `VocabBody` sau khi tra API; từ bị API bỏ thì không nạp (không gửi từ chỉ có ngữ cảnh).

**Gửi.** Như Phase 5, `origin` là giá trị `--origin` (bắt buộc, ví dụ `Pride and Prejudice`). Từ đã có từ trước: server ghi đè `entry` nhưng giữ `context` cũ khi bản mới không có (câu hỏi 7), nên nạp sách sau khi nạp API thêm được ngữ cảnh.

**`--dry-run`** in danh sách ứng viên kèm ngữ cảnh và không gọi API; `--dry-run --lookup` tra API và in body, không gửi.

## Tasks & Steps

- [ ] `book.rs`: hàm thuần `candidates(text, min_length, max) -> Vec<(word, context)>`.
- [ ] `stopwords.rs`: hằng mảng từ chức năng.
- [ ] Lệnh con `Book { path, origin, max, min_length, dictionary_url, server, dry_run, lookup }`.
- [ ] Unit test với `sample.txt`: phần đầu và cuối Gutenberg bị bỏ; từ ngắt dòng bằng gạch nối được nối lại; tên riêng chỉ viết hoa bị loại; từ chỉ xuất hiện một lần bị loại; ngữ cảnh là câu đầu tiên chứa từ; câu dài bị cắt có `…`; `--max` giới hạn số từ.
- [ ] Thử cục bộ với Worker `wrangler dev` và Supabase cục bộ: `ingest book sample.txt --origin sample --max 5`, kiểm `select word, entry->>'context' from vocab_words where origin = 'sample'` mọi dòng có `context`. Gọi API thật tối đa 10 request.

## Verification

- `cargo test -p cli` pass.
- `cargo clippy --workspace -- -D warnings` sạch.
- `os-widget ingest book crates/cli/tests/fixtures/book/sample.txt --origin sample --dry-run` in các từ kèm câu lấy đúng từ file.
- Vòng thử cục bộ: mọi từ của `origin = 'sample'` có `context` không rỗng.

## Risk Assessment

- Chọn từ chưa tốt (quá dễ hoặc quá hiếm): ngưỡng là cờ dòng lệnh; operator chỉnh khi nạp thật ở Phase 7 sau khi xem `--dry-run`.
- File sách có bản quyền lọt vào repo: fixture là văn bản tự viết; sách thật nằm ngoài repo và chỉ truyền bằng đường dẫn.
- Sách lớn (vài MB): xử lý trong bộ nhớ, một lần; không vấn đề với CLI chạy trên máy.

## Rollback

Revert commit; chưa ghi dữ liệu live.
