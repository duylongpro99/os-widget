# Hạn mức Cloudflare Workers gói miễn phí

Ngày tra: 2026-11-22. Phiên bản wrangler: `4.166.0` (từ `npx wrangler --version`); mọi lệnh wrangler sau này dùng `npx wrangler@4.166.0`.

## CPU mỗi request

- 10 ms CPU cho mỗi request HTTP ở gói Free (gói Paid: tối đa 5 phút, mặc định 30 giây). Nguồn: https://developers.cloudflare.com/workers/platform/limits/#cpu-time (tra 2026-11-22).
- Thời gian chờ mạng (`fetch()`, truy vấn DB) không tính vào CPU. Nguồn: https://developers.cloudflare.com/workers/platform/limits/#cpu-time (tra 2026-11-22).
- CPU khởi động (phân tích và chạy global scope, bao gồm khởi tạo Wasm) có hạn mức riêng là 1 giây. Tài liệu không nói rõ phần này có cộng vào 10 ms của request hay không; lỗi vượt hạn mức khởi động là "Script startup exceeded CPU time limit" (mã 10021), tức là được đo bằng CPU nhưng tách khỏi hạn mức của request. Vì không có câu khẳng định, Phase 5 cần đo cả request đầu (cold) lẫn request sau (warm). Nguồn: https://developers.cloudflare.com/workers/platform/limits/#worker-startup-time (tra 2026-11-22).

## Dung lượng Worker

- Không còn hạn mức dung lượng sau nén; chỉ tính dung lượng chưa nén, tối đa 64 MiB ở cả gói Free và Paid. Nguồn: https://developers.cloudflare.com/workers/platform/limits/#worker-size (tra 2026-11-22).
- Khác với giả định khoảng 3 MB sau nén trong plan. Theo rủi ro của Phase 1, Phase 5 dùng con số trong tài liệu (64 MiB chưa nén) làm ngưỡng, và vẫn ghi dung lượng sau nén để tham khảo.

## Cron Trigger

- Tối đa 5 Cron Trigger mỗi tài khoản ở gói Free (Paid: 1.000). Nguồn: https://developers.cloudflare.com/workers/platform/limits/#account-plan-limits (tra 2026-11-22).
- CPU mỗi lần chạy Cron Trigger ở gói Free: 10 ms. Nguồn: https://developers.cloudflare.com/workers/platform/limits/#cpu-time (tra 2026-11-22).
- Nhịp tối thiểu: tài liệu không ghi thành hạn mức; cú pháp cron có trường phút (0–59) và ví dụ `* * * * *` được mô tả là "At every minute", nên nhịp nhỏ nhất là 1 phút. Nguồn: https://developers.cloudflare.com/workers/configuration/cron-triggers/ (tra 2026-11-22).
