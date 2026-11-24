---
title: "M4: Từ vựng"
description: "Hoàn thành Giai đoạn 4 của roadmap: bảng vocab_words và settings, endpoint nạp từ, lệnh ingest từ Free Dictionary API và sách .txt, Cron Trigger gửi một từ theo chu kỳ chỉnh bằng settings, thẻ vocab đầy đủ có phát âm ở popup và danh sách, bố cục rút gọn ở widget."
status: pending
priority: P1
effort: 30h
branch: main
tags: [feature, backend, database, cli, macos, swift]
blockedBy: []
blocks: []
created: 2026-11-24
---

# M4: Từ vựng

## Overview

Hoàn thành Giai đoạn 4 của [roadmap](../../docs/roadmap.md#giai-đoạn-4-từ-vựng) trên server đã nghiệm thu ở [plan M1](../261123-0159-m1-server/plan.md) và app thanh menu của [plan M2](../261123-1547-m2-menu-bar-app/plan.md). Kết thúc plan này, bộ từ riêng nằm trên Supabase, được nạp bằng `os-widget ingest` từ Free Dictionary API và từ sách `.txt`, một Cron Trigger của Worker gửi một từ chưa gửi thành mục `vocab` theo chu kỳ đọc từ bảng `settings`, và app hiện thẻ `vocab` đầy đủ có nút phát âm ở popup và danh sách, cùng bố cục rút gọn ở widget của M3.

Thiết kế theo [architecture.md](../../docs/architecture.md) §3.2 (body `vocab`), §4.1 đến §4.4 (API, mã Rust, cơ sở dữ liệu, bộ từ vựng), §6 (phát âm), §8 (hạn mức, CPU isolate lạnh 16–21 ms), §9 (rủi ro CPU). Yêu cầu theo [prd.md](../../docs/prd.md) FR-15, FR-24 đến FR-27, §10 tiêu chí 5, §11 câu 1.

Quyết định D4 của operator (2026-11-24 14:12, nguyên văn): "dictionaryapi.dev + .txt (Recommended)". Nạp dùng Free Dictionary API (`https://api.dictionaryapi.dev`, miễn phí, không cần khoá) và sách văn bản thuần `.txt`; EPUB để sau.

## Preconditions

1. Worker `https://os-widget.longdaobk17.workers.dev` vẫn qua `scripts/acceptance-server.sh`; `cargo test --workspace` (92) và `swift test` (127) pass trên `main` tại `2f7bf2e`.
2. Docker chạy được để dựng Supabase cục bộ (`supabase start`) như Phase 1 của M1.
3. Phase 9 chỉ mở khi Phase 4 của [plan M3](../261124-1415-m3-widget/plan.md) (giao diện widget và `CompactCardView`, cần Phase 1 và 2 của M3) đã merge.
4. Bước live (đánh dấu **[operator]** trong phase) chỉ chạy khi supervisor đã hỏi và operator đồng ý.

## Done means

Điều kiện hoàn thành của roadmap Giai đoạn 4:

1. **PRD §10.5.** Một thẻ từ vựng hiện đủ các trường ở FR-15 (từ, phiên âm, từ loại, nghĩa, câu ví dụ, ngữ cảnh, từ đồng nghĩa và trái nghĩa, nút phát âm) ở popup và danh sách, và bấm nút thì phát âm được (`audio_url` khi có, bộ đọc hệ thống khi không).
2. Nạp một danh sách từ qua API từ điển tạo ra các mục đủ trường; nạp lại không tạo bản trùng.
3. Nạp một cuốn sách tạo ra các từ kèm câu ngữ cảnh lấy từ sách.
4. Đổi chu kỳ trong `settings` có hiệu lực mà không phải deploy lại.
5. Khi hết từ, hệ thống dừng hoặc quay vòng đúng theo cấu hình, và không gửi mục rỗng hoặc lỗi (FR-27).

Thêm: CPU của mỗi lần chạy cron được đo trên bản deploy và ghi vào architecture §8; `cargo test --workspace`, `cargo clippy --workspace -- -D warnings`, `swift test` pass; `scripts/acceptance-server.sh` vẫn pass; architecture, roadmap và PRD ghi đúng những gì đã làm.

### Ánh xạ yêu cầu sang phase

| Yêu cầu | Phase |
|---|---|
| Roadmap: view `vocab` đầy đủ ở popup và danh sách | 8 |
| Roadmap: bố cục rút gọn ở widget | 9 (sau M3) |
| Roadmap: phát âm bằng bộ đọc của hệ thống, hoặc `audio_url` nếu có | 5 (lấy `audio_url`), 8 (phát) |
| Roadmap: bảng `vocab_words` và `settings`; endpoint nạp từ | 2 (bảng, hàm SQL), 3 (validate một từ), 4 (`POST /vocab/words`) |
| Roadmap: lệnh `ingest` từ API từ điển trước, sau đó từ sách | 1 (đo độ phủ API, đã xong), 5 (API), 6 (sách `.txt`) |
| Roadmap: Cron Trigger gửi một từ chưa gửi theo chu kỳ, mặc định 1 giờ, chỉnh bằng `settings` | 2 (`vocab_tick`), 4 (Cron Trigger), 7 (deploy, đo CPU) |
| Hoàn thành khi 1 (PRD §10.5) | 6 (ngữ cảnh), 8, 10 |
| Hoàn thành khi 2 (danh sách từ qua API, nạp lại không trùng) | 2, 4, 5, 7 |
| Hoàn thành khi 3 (sách tạo từ kèm câu ngữ cảnh) | 6, 7 |
| Hoàn thành khi 4 (đổi chu kỳ không cần deploy) | 2 (test cục bộ), 7 (kiểm live) |
| Hoàn thành khi 5 (hết từ: dừng hoặc quay vòng) | 2 (test cục bộ), 7 |
| PRD §11 câu 1 (chốt API và định dạng sách) | 1, 10 (ghi vào PRD và roadmap) |

## Phases

| # | Phase | Status | Loại | Phụ thuộc |
|---|-------|--------|---|---|
| 1 | [Kiểm độ phủ trường của API từ điển](./phase-01-kiem-do-phu-api.md) | Completed | Server | Không |
| 2 | [Schema `vocab_words`, `settings` và hàm gửi từ](./phase-02-schema-va-ham-gui-tu.md) | Pending | Server | Không |
| 3 | [Envelope: kiểm một từ vựng](./phase-03-envelope-kiem-tu-vung.md) | Pending | Server | Không |
| 4 | [Worker: `POST /vocab/words` và Cron Trigger](./phase-04-worker-nap-tu-va-cron.md) | Pending | Server | 2, 3 |
| 5 | [CLI `ingest words` từ Free Dictionary API](./phase-05-cli-ingest-tu-api.md) | Pending | Server | 1, 3 |
| 6 | [CLI `ingest book` từ sách `.txt`](./phase-06-cli-ingest-tu-sach.md) | Pending | Server | 5 |
| 7 | [Deploy, đo CPU cron và nghiệm thu server](./phase-07-deploy-va-nghiem-thu-server.md) | Pending | Server, có bước **[operator]** | 2, 4, 5, 6 |
| 8 | [Thẻ `vocab` đầy đủ và phát âm](./phase-08-the-tu-vung-va-phat-am.md) | Pending | Client | Không (xếp lịch tránh cook M3 sửa cùng file) |
| 9 | [Bố cục rút gọn `vocab` ở widget](./phase-09-bo-cuc-rut-gon-widget.md) | Pending | Client | 8; M3 Phase 4 |
| 10 | [Nghiệm thu PRD §10.5 và cập nhật tài liệu](./phase-10-nghiem-thu-va-tai-lieu.md) | Pending | Client và tài liệu | 7, 8, 9 |

Server-only (1 đến 7) không chạm `apps/`, nên chạy song song được với cook của M3. Tối đa 3 session song song (quyết định của operator 2026-11-24).

```text
Server:  2 ──┐
             ├──> 4 ──┐
         3 ──┤        ├──> 7 ──┐
             └──> 5 ──> 6 ──┘  │
Client:  8 ─────────────> 9 ───┼──> 10
         M3 Phase 4 ──────┘    │
```

Gợi ý xếp lịch với 3 session: đợt 1 chạy 2, 3 và 8 (8 chỉ khi không có cook M3 đang sửa `Cards/CardView.swift` hoặc `Model/Item.swift`); đợt 2 chạy 4 và 5; đợt 3 chạy 6; rồi 7; 9 khi M3 xong; 10 cuối cùng.

### Sở hữu file

| Phase | Sở hữu (tạo hoặc sửa) |
|---|---|
| 1 | `plans/261124-1415-m4-vocab/reports/api-coverage.md`, `plans/261124-1415-m4-vocab/reports/api-samples/*` (đã tạo khi viết plan) |
| 2 | `supabase/migrations/20261124000000_vocab.sql`, `supabase/tests/vocab_tick.test.sql` |
| 3 | `crates/envelope/src/vocab.rs`, `crates/envelope/src/parse.rs`, `crates/envelope/src/lib.rs`, `crates/envelope/tests/vocab.rs` |
| 4 | `crates/worker/src/lib.rs`, `crates/worker/src/vocab.rs`, `crates/worker/wrangler.toml` |
| 5 | `crates/cli/src/main.rs`, `crates/cli/src/ingest/mod.rs`, `crates/cli/src/ingest/dictionary.rs`, `crates/cli/tests/fixtures/dictionary/*.json`, `crates/cli/Cargo.toml` |
| 6 | `crates/cli/src/ingest/book.rs`, `crates/cli/src/ingest/stopwords.rs`, `crates/cli/src/ingest/mod.rs` (thêm lệnh `book`), `crates/cli/tests/fixtures/book/*.txt` |
| 7 | `scripts/acceptance-vocab.sh`, `plans/261124-1415-m4-vocab/reports/acceptance-server.md`; bước live trên Supabase và Cloudflare |
| 8 | Dưới `apps/macos/OSWidgetKit/`: `Sources/OSWidgetKit/Model/VocabContent.swift`, `Sources/OSWidgetKit/Model/Item.swift` (thêm `ItemContent.vocab`), `Sources/OSWidgetKit/Cards/VocabCardView.swift`, `Sources/OSWidgetKit/Cards/Pronunciation.swift`, `Sources/OSWidgetKit/Cards/CardView.swift`, `Sources/OSWidgetKit/Cards/CardPreviews.swift`, `Tests/OSWidgetKitTests/VocabTests.swift`, `Tests/OSWidgetKitTests/CardsTests.swift`, `Tests/OSWidgetKitTests/Fixtures/items.json`; một dòng `case .vocab: .fallback` trong `Sources/OSWidgetKit/Cards/Compact/CompactCardView.swift` nếu M3 Phase 4 đã merge |
| 9 | Dưới `apps/macos/OSWidgetKit/`: `Sources/OSWidgetKit/Cards/Compact/CompactVocabView.swift`; nhánh `vocab` trong `Sources/OSWidgetKit/Cards/Compact/CompactCardView.swift` và `Tests/OSWidgetKitTests/CompactCardTests.swift` (file của M3, sửa sau khi M3 Phase 4 xong) |
| 10 | `plans/261124-1415-m4-vocab/reports/acceptance.md`, `docs/architecture.md`, `docs/roadmap.md`, `docs/prd.md` |

Phase 5 và 6 cùng sửa `crates/cli/src/ingest/mod.rs` nên chạy nối tiếp. Phase 8 và các phase của M3 có thể cùng sửa `Cards/CardView.swift` và `Model/Item.swift`: supervisor không cho hai cook sửa hai file này cùng lúc; cook đến sau rebase lên commit của cook trước. Thêm `ItemContent.vocab` làm `switch` đủ trường hợp trong `CompactCardView.variant(for:)` (M3 Phase 4) không biên dịch, nên Phase 8 hoặc cook M3 rebase sau thêm `case .vocab: .fallback` (xem Phase 8, mục Risk).

## Thiết kế đã chốt

- **Nạp chạy trên máy** (architecture §4.4). `os-widget ingest` gọi API từ điển, dựng `VocabBody`, kiểm bằng hàm của crate `envelope`, gửi theo lô tới `POST /vocab/words` bằng token publish. Từ không đủ trường bắt buộc bị bỏ và được báo trên màn hình.
- **Cron rẻ nhất có thể.** Mỗi lần chạy, Worker chỉ gọi một RPC `POST /rest/v1/rpc/vocab_tick` và ghi một dòng log. Toàn bộ logic (đọc `settings`, kiểm tới hạn, chọn từ, xử lý hết từ, tạo mục `items`, đánh dấu `sent_at`) nằm trong hàm SQL `vocab_tick()` chạy trong một transaction có khoá advisory, nên hai lần chạy chồng nhau không gửi trùng. Trigger hiện có trên `items` tự ghi `item.created`, nên client nhận mục `vocab` như mọi mục khác.
- **Cấu hình nằm trong `settings`**, đọc ở mỗi lần chạy: `vocab_enabled`, `vocab_interval_minutes`, `vocab_when_exhausted`, `vocab_priority`, `vocab_item_ttl_seconds`; thời điểm gửi gần nhất lưu ở `vocab_last_sent_at`. Đổi một dòng là có hiệu lực ở lần chạy cron kế tiếp.
- **Nhịp cron cố định ngắn**, mặc định `*/5 * * * *` (câu hỏi 5). Một lần chạy tới hạn khi `now() >= vocab_last_sent_at + interval - 1 phút`; phút trừ đi bù cho độ lệch giữa các lần chạy.
- **Đường dự phòng không cần sửa mã Worker:** nếu đo cho thấy lần chạy cron bị Cloudflare chặn vì vượt CPU, cùng hàm `vocab_tick()` được lên lịch bằng `pg_cron` (như `purge_old_rows`) và gỡ Cron Trigger. Đây là bước **[operator]** ở Phase 7.

## Scope Challenge

- Có sẵn: crate `envelope` với `VocabBody` và `Meaning`; `envelope::parse` đã kiểm `word`, `meanings`, `definition`, `audio_url`; Worker với `supabase::rows` gọi PostgREST; CLI `os-widget` với `ureq` và `clap`; `pg_cron` đã bật trên project; app có view dự phòng hiện mục `vocab`.
- Phạm vi: đúng năm gạch đầu dòng và năm tiêu chí của roadmap Giai đoạn 4. Giữ nguyên phạm vi (HOLD).
- Độ phức tạp: 10 phase, mỗi phase một cook session; khoảng 20 file mới hoặc sửa, một migration, không crate mới, không phụ thuộc Swift ngoài.

## Out of scope

- EPUB, PDF và mọi định dạng sách khác ngoài `.txt` (quyết định D4).
- API từ điển khác ngoài Free Dictionary API, kể cả làm nguồn dự phòng cho từ thiếu IPA.
- Đưa từ về dạng gốc (lemmatization), dịch nghĩa sang tiếng Việt, lặp lại theo khoảng cách (spaced repetition).
- Endpoint đọc hoặc sửa `settings` qua Worker; cấu hình được sửa bằng SQL trên Supabase.
- Phát âm từ widget (architecture §6), báo lỗi trên UI khi server không phản hồi (Giai đoạn 5).

## Constraints

- Chỉ gói miễn phí của Cloudflare và Supabase; Cron Trigger dùng đúng một trigger.
- Worker gọi Supabase qua PostgREST bằng `worker::Fetch`; logic cron nằm trong SQL, không nằm trong Rust.
- Crate `envelope` vẫn build cho `wasm32-unknown-unknown`; Worker và CLI dùng chung một hàm kiểm từ vựng.
- Không commit secret, chuỗi kết nối Postgres hay file sách có bản quyền. Kiểm bằng `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'`.
- Gọi API từ điển tuần tự, cách nhau ít nhất 300 ms, thử lại 429 và 5xx tối đa 3 lần.
- Popup mặc định không phát âm thanh (FR-7): chỉ phát khi người dùng bấm nút.
- Không làm hỏng `scripts/acceptance-server.sh` và `scripts/acceptance-menu-bar.sh`.

## Stop and ask only if

- Lần chạy cron bị Cloudflare chặn vì CPU và operator chưa duyệt đường `pg_cron`.
- Thiếu quyền Cloudflare hoặc Supabase, hoặc `supabase db push` lỗi.
- Free Dictionary API trả 429 kéo dài hoặc đổi định dạng so với `reports/api-samples/`.
- Một tiêu chí chỉ đạt được nếu đổi API ở architecture §4.1 hoặc định dạng `vocab` ở §3.2 theo cách chưa nêu ở đây.
- Plan M3 đặt bố cục rút gọn theo `kind` ở chỗ Phase 9 không thêm nhánh `vocab` được mà không sửa phần chung của M3.

## Câu hỏi cần operator trả lời

Gửi cho supervisor `supervisor-project` ngày 2026-11-24. Câu 5 đến 7 do supervisor quyết; câu 1 đến 4 là lựa chọn sản phẩm, đang chờ operator (D5 đến D8). Trong lúc chờ, đề xuất là giá trị mặc định của plan.

| # | Câu hỏi | Đề xuất | Phase bị ảnh hưởng | Trạng thái |
|---|---|---|---|---|
| 1 | Khi đã gửi hết từ, mặc định dừng hay quay vòng (`vocab_when_exhausted`)? | Quay vòng (`rotate`): xoá `sent_at` của mọi từ rồi gửi tiếp, không gửi lại ngay từ vừa gửi. Dừng làm thẻ biến mất lặng lẽ cho tới khi nạp thêm. Đổi được bất cứ lúc nào bằng một dòng SQL. | 2, 7 | Chờ operator (D5); mặc định theo đề xuất |
| 2 | Sách `.txt` nào nạp đầu tiên, và danh sách từ API ban đầu là gì? | Sách: một bản UTF-8 từ Project Gutenberg operator đang muốn đọc, mặc định "Pride and Prejudice" (Gutenberg #1342); file nằm ngoài repo, nạp tối đa 50 từ. Danh sách API: 17 từ đủ trường trong lần đo cộng danh sách riêng của operator nếu có. | 6, 7, 10 | Chờ operator (D6); mặc định theo đề xuất |
| 3 | Mục `vocab` gửi với `priority` nào? | `normal`: popup tự mở mỗi giờ, và người dùng tắt riêng `vocab` ở menu nếu phiền (FR-10c, đã có ở M2). Lưu ở `vocab_priority`, đổi được không cần deploy. | 2 | Chờ operator (D7); mặc định theo đề xuất |
| 4 | Mục `vocab` sống bao lâu (`ttl`)? | 1 ngày (86400 giây, như ví dụ ở architecture §3.1), để danh sách không giữ 168 thẻ mỗi tuần. Lưu ở `vocab_item_ttl_seconds`. | 2 | Chờ operator (D8); mặc định theo đề xuất |
| 5 | Nhịp cron và nơi chạy? | Cron Trigger của Worker `*/5 * * * *` (288 lần mỗi ngày, chu kỳ chính xác tới 5 phút) theo roadmap, đo CPU một giờ sau deploy; chỉ chuyển sang `pg_cron` nếu có lần chạy bị chặn vì CPU. Cron Trigger gọi PostgREST nên còn giữ project Supabase không bị tạm dừng; `pg_cron` không tốn CPU Worker nhưng chưa rõ có tính là hoạt động không. | 4, 7 | Đã chốt (supervisor) |
| 6 | Thứ tự chọn từ chưa gửi? | Ngẫu nhiên trong các từ chưa gửi, để từ của cùng một sách không tới theo đúng thứ tự xuất hiện. | 2 | Đã chốt (supervisor) |
| 7 | Nạp lại một từ đã có thì làm gì? | Ghi đè `entry` và `origin` bằng bản mới, giữ `added_at` và `sent_at`; riêng `context`: nếu bản mới không có thì giữ `context` cũ, để nạp từ API sau khi nạp từ sách không làm mất câu ngữ cảnh. | 2, 4 | Đã chốt (supervisor) |

## Operator answers

Ngày 2026-11-24 (khoảng 14:20), supervisor `supervisor-project` trả lời:

| # | Câu trả lời | Thay đổi trong plan |
|---|---|---|
| 5 | Chấp nhận: Cron Trigger `*/5 * * * *` gọi một RPC `vocab_tick`; đo CPU bằng `wrangler tail` một giờ sau deploy; chỉ chuyển sang `pg_cron` cùng hàm nếu có lần chạy bị chặn vì CPU (quyết định của supervisor). | Không, giữ như Phase 4 và 7. |
| 6 | Chấp nhận thứ tự ngẫu nhiên (quyết định của supervisor). | Không, giữ như Phase 2. |
| 7 | Chấp nhận: ghi đè `entry` và `origin`, giữ `added_at` và `sent_at`, giữ `context` cũ khi bản mới không có (quyết định của supervisor). | Không, giữ như Phase 2 và 4. |
| 1–4 | Chờ operator (D5 đến D8). | Dùng đề xuất làm mặc định; khi có câu trả lời, cập nhật giá trị mặc định ở Phase 2 và bước G3 của Phase 7. |

## Validation Log

### Session 1 (2026-11-24)

Câu 5 đến 7 đã chốt và khớp thiết kế trong Phase 2, 4, 7; không phase nào phải đổi. Câu 1 đến 4 chỉ ảnh hưởng giá trị mặc định trong migration của Phase 2 và dữ liệu nạp ở Phase 7, nên không chặn cook nào trước Phase 2.

<!-- slug: m4-vocab -->
