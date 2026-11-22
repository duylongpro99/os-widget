# Kết quả thử nghiệm D: CPU và dung lượng của Worker Rust

Ngày đo: 2026-11-22 (giờ Asia/Saigon). Worker: https://os-widget.longdaobk17.workers.dev.

## Kết luận

Worker Rust **trượt** ngưỡng CPU đã chốt: p99 của `POST /items` là 11 ms và của `GET /events` là 7 ms ở cả hai lần đo, trong khi ngưỡng là p99 ≤ 5 ms ở cả hai endpoint (p99 trong khoảng 5–10 ms vẫn tính là trượt). Dung lượng thì đạt. Operator đã xem kết quả và quyết định giữ Rust dù trượt ngưỡng (xem mục Quyết định).

## Cách đo

- Tải: `scripts/measure-worker.sh <url>` gửi tuần tự 150 `POST /items` (title khác nhau, `dedupe_key` null), một request dò `GET /events?since=0&probe=1` để lấy `seq` mới nhất, rồi 150 `GET /events?since=<seq mới nhất − 5>` (mỗi lần trả 5 sự kiện kèm mục).
- Nguồn CPU: `npx wrangler@4.166.0 tail os-widget --format json` chạy trong suốt lần đo; mỗi sự kiện tail có trường `cpuTime` (ms, số nguyên) của đúng một invocation. p50/p99 tự tính theo nearest-rank, tách theo method và path, bỏ request dò. Không dùng được Workers Logs qua API vì token OAuth của wrangler không có quyền observability; GraphQL Analytics không tách theo path.
- Tail không bắt đủ 300 request (Cloudflare có thể lấy mẫu hoặc làm rơi sự kiện tail), nên n dưới đây là số invocation có trong dữ liệu CPU, không phải số request đã gửi.
- Dữ liệu thô (không có token, không có IP): [`d-cpu-raw.csv`](./d-cpu-raw.csv).
- Phiên bản: crate `worker` 0.9.0, `worker-build` 0.9.0, wrangler 4.166.0. Version đo hai lần chạy: `9bf54520-c2e9-423b-aba7-62e92ea527a8`.

## CPU theo endpoint

| Lần | Giờ bắt đầu | Endpoint | n | p50 | p90 | p99 | max | Số request > 5 ms | Lỗi script |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 15:24:35 | `POST /items` | 140 | 2 ms | 3 ms | 11 ms | 11 ms | 5 | 0 |
| 1 | 15:24:35 | `GET /events` | 143 | 3 ms | 4 ms | 7 ms | 8 ms | 5 | 0 |
| 2 | 15:30:20 | `POST /items` | 147 | 2 ms | 3 ms | 11 ms | 13 ms | 4 | 0 |
| 2 | 15:30:20 | `GET /events` | 143 | 3 ms | 4 ms | 7 ms | 9 ms | 5 | 0 |

- Hai lần cách nhau khoảng 6 phút cho p99 giống hệt, nên không có biến động bất thường (điều kiện lệch hơn 2 lần không xảy ra).
- `POST /items`: phần lớn 1–2 ms. Các giá trị 8–13 ms gần như chỉ rơi vào khoảng 20 request đầu của mỗi lần chạy, phù hợp với việc request đi vào isolate mới đang khởi động Wasm. Sau đó chỉ còn vài lần chạm 5 ms.
- `GET /events`: p90 4 ms, có đuôi 5–9 ms rải rác suốt lần chạy (khoảng 3–4% request trên 5 ms).
- Lỗi script: 0 trên 300 request ở cả hai lần.

## Cold start

Deploy lại cùng mã từ `crates/worker` bằng `npx wrangler@4.166.0 deploy` (wrangler báo `Worker Startup Time: 11 ms`). Lần deploy này đổi version đang chạy thành `129b5371-ba75-4b33-bb48-e0310d3c15df`; mã không đổi.

| Thứ tự sau deploy | Request | CPU | Wall |
|---|---|---|---|
| 1 (đầu tiên) | `POST /items` | 16 ms | 460 ms |
| 2–5 | `POST /items` | 16, 3, 3, 21 ms | 60–99 ms |
| 6–8 | `GET /events` | 6, 10, 1 ms | 50–77 ms |

CPU khởi động hoặc warm-up của isolate mới **có** được tính vào CPU của request: request đầu tiên tốn 16 ms so với mức 1–2 ms khi đã ấm, và các request trúng isolate mới khác lên tới 21 ms. Các con số 16–21 ms vượt hạn mức 10 ms của gói Free, nhưng `outcome` của mọi request vẫn là `ok` (không bị chặn).

## Dung lượng

| Đo | Giá trị | Hạn mức (`limits.md`) | Đánh giá |
|---|---|---|---|
| Tổng (chưa nén) | 563.08 KiB | 64 MiB chưa nén | Đạt |
| Sau gzip | 191.37 KiB | Không còn hạn mức sau nén; ghi để tham khảo | — |

Không cần thử `wasm-opt -Oz` vì dung lượng đã nằm dưới hạn mức.

## Dọn dữ liệu

Sau khi đo, `items` và `events` có 305 dòng mỗi bảng (300 của hai lần đo và 5 của bước cold start). Đã xoá bằng PostgREST với khoá service role (`DELETE events?seq=gte.0`, `DELETE items?id=not.is.null`, đều 204); sau đó cả hai bảng trả `[]`.

## Quyết định

Theo ngưỡng đã chốt, Rust trượt: p99 của `POST /items` là 11 ms và của `GET /events` là 7 ms, cả hai đều lớn hơn 5 ms; dung lượng đạt. Operator đã xem các con số này và trả lời "keep Rust" (2026-11-22 15:34, quyết định D6 trong sổ quyết định của supervisor). Vì vậy không viết `worker-ts/`.

Rủi ro được chấp nhận:

- Khi đã ấm, CPU p50 chỉ 2–3 ms; đuôi p99 đến chủ yếu từ các request trúng isolate mới đang khởi động Wasm.
- CPU cold start 16–21 ms vượt hạn mức 10 ms của gói Free. Lần đo này không request nào bị chặn (`outcome` đều là `ok`), nhưng Cloudflare không cam kết sẽ luôn bỏ qua như vậy.

Quyết định: Rust — trượt ngưỡng p99 ≤ 5 ms ở cả hai endpoint (11 ms và 7 ms) nhưng operator chọn giữ Rust và chấp nhận rủi ro ở trên.
