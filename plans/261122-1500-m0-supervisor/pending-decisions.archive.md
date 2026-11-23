# Answered decisions

## D1 · p02, p04 · ANSWERED · 2026-11-22 15:02
Câu hỏi: Supabase cho os-widget: tài khoản đang chỉ có project "affiliate-products" (INACTIVE). Cho phép phiên cook tạo project mới và dùng khoá thế nào?
- A (đề xuất): Cho phiên cook chạy `supabase projects create os-widget` (gói Free, region ap-southeast-1, mật khẩu DB sinh ngẫu nhiên lưu vào macOS Keychain), lấy service role key bằng `supabase projects api-keys` và pipe thẳng vào `wrangler secret put`, không ghi ra file nào.
- B: Bạn tự tạo project trên dashboard rồi báo project ref; khoá service role bạn tự `wrangler secret put` khi phiên cook nhắn.
- C: Dùng lại project affiliate-products (phải bật lại, trộn dữ liệu với dự án khác).
Chặn: m0-p01-02-cook (bước supabase link/db push), m0-p04-cook
Seen: [x]
Answer: 2026-11-22 15:05 (file) A

## D2 · p04, p05 · ANSWERED · 2026-11-22 15:02
Câu hỏi: Cho phép deploy Worker spike lên tài khoản Cloudflare đang đăng nhập (Longdaobk17@gmail.com's Account, workers.dev, gói Free) và chạy 300 request đo trên bản deploy?
- A (đề xuất): Cho phép; Worker có token tạm SPIKE_TOKEN, xoá dữ liệu thử sau khi đo.
- B: Chỉ deploy khi bạn có mặt để xác nhận từng lần.
Chặn: m0-p04-cook, m0-p05-cook
Seen: [x]
Answer: 2026-11-22 15:05 (file) A

## D3 · p03 · ANSWERED · 2026-11-22 15:02
Câu hỏi: Máy chưa cài Xcode.app (xcode-select đang trỏ Command Line Tools; plan ghi nhầm là đã có xcodebuild). Phase 3 (app thử nghiệm A, widget, App Group) cần Xcode đầy đủ + Apple ID + Team ID. Xử lý thế nào?
- A (đề xuất): Bạn cài Xcode từ App Store (~3–10 GB, 30–60 phút), chạy `sudo xcode-select -s /Applications/Xcode.app`, đăng nhập Apple ID trong Xcode và gửi Team ID (10 ký tự). Trong lúc chờ, tôi chạy Phase 1, 2, 4, 5 trước.
- B: Hoãn thử nghiệm A sang sau M0; Phase 6 ghi A "chưa bắt đầu".
Chặn: m0-p03-cook, Phase 6 (cần kết quả của 3)
Seen: [x]
Answer: 2026-11-22 15:05 (file) Tôi đã cài xCode từ app store rồi mà

## D4 · p03 · ANSWERED · 2026-11-22 15:05
Câu hỏi: Tôi chưa thấy Xcode.app trên máy (không có trong /Applications, Spotlight không tìm thấy, xcode-select vẫn trỏ CommandLineTools). Có thể App Store vẫn đang tải. Bạn kiểm tra giúp?
- A (đề xuất): Bạn mở App Store xem tiến độ; khi xong chạy `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, mở Xcode một lần (đồng ý license), đăng nhập Apple ID (Settings → Accounts) rồi trả lời ở đây kèm Team ID (10 ký tự). Phase 2, 4, 5 vẫn chạy trong lúc chờ.
- B: Xcode nằm ở chỗ khác — cho tôi đường dẫn.
Chặn: m0-p03-cook, Phase 6
Seen: [x]
Answer: 2026-11-22 15:13 (file) Đã cài đặt xong

## D6 · Phase 5 (D) · ANSWERED · 2026-11-22 15:33
Rust Worker trượt ngưỡng đã chốt (p99 ≤ 5 ms): POST /items p99 11 ms (p50 2), GET /events p99 7 ms (p50 3), giống hệt ở 2 lần đo (n 140–147/endpoint); cold start 16–21 ms CPU. Dung lượng 563 KiB đạt. Xử lý thế nào?
- A (Đề xuất): Giữ ngưỡng → Quyết định TypeScript. Phiên cook viết worker-ts/ (cùng 2 endpoint) và đo y hệt cách đo Rust; nếu TS cũng trượt thì quay lại hỏi bạn.
- B: Viết TS và đo cùng cách trước, rồi bạn chọn Rust/TS khi có số của cả hai (chưa chốt quyết định).
- C: Đổi ngưỡng (vd. p99 ≤ 10 ms, hoặc chỉ tính request ấm) → Rust vẫn trượt POST 11 ms nếu ≤ 10 ms; đạt nếu chỉ tính ấm.
Chặn: m0-p05-cook, Phase 6
Seen: [ ]
Answer: 2026-11-22 15:34 (dialog) keep Rust

## D5 · p03 · ANSWERED · 2026-11-22 15:13
Câu hỏi: Xcode 27.2 đã chạy được (cảm ơn). Nhưng Xcode chưa có tài khoản Apple nào: không có team, `security find-identity` báo 0 chứng chỉ ký. Bạn đăng nhập Apple ID giúp và gửi Team ID?
- A (đề xuất): Mở Xcode → Settings → Accounts → "+" → Apple ID, đăng nhập; chọn Personal Team, bấm "Manage Certificates…" → "+" → "Apple Development". Trả lời `D5: <Team ID 10 ký tự>` (thấy ở Accounts hoặc trong chứng chỉ). Trong lúc chờ, phiên m0-p03-cook viết sẵn project và build không ký.
- B: Hoãn thử nghiệm A; chỉ giữ code chưa ký.
Chặn: bước ký và cài app của m0-p03-cook, Phase 6
Seen: [x]
Answer: 2026-11-22 21:43 (file) I added new cert but it is not showing teamid

## D7 · Phase 3 (A, C ngày 1) · ANSWERED · 2026-11-22 21:48
Probe app đã cài (21:47). Nhờ bạn làm Phần A (thêm widget "Probe", bấm "Ghi dữ liệu") và Phần C (gõ TextEdit khi panel hiện) theo hướng dẫn trong chat, rồi báo lại kết quả.
- A: widget hiện mốc thời gian hay "App Group: lỗi"; đổi sau bao lâu; có hộp thoại xin quyền không (nguyên văn); menu ghi "App Group: …" gì.
- C: panel có hiện không; ký tự gõ tiếp có vẫn vào TextEdit không; thanh menu còn ghi "TextEdit" không.
Chặn: m0-p03-cook (báo cáo ngày 1), m0-p03-review, Phase 6
Seen: [x]
Answer: 2026-11-22 21:49 (file) A, Làm như thế nào?

## D8 · Phase 3 (A, C ngày 1) · ANSWERED · 2026-11-22 21:49
Bạn hỏi cách làm ở D7: hướng dẫn từng bước nằm trong /Users/onedayin20902/personal/os-widget/plans/261122-1500-m0-supervisor/huong-dan-d7-widget-textedit.md. Làm xong Phần A (widget) và Phần C (TextEdit) rồi ghi kết quả vào đây.
- A: (a) widget hiện mốc thời gian hay "App Group: lỗi"; (b) đổi sau bao lâu; (c) có hộp thoại xin quyền không (nguyên văn); (d) menu ghi "App Group: …" gì.
- C: (a) panel có hiện không; (b) chữ gõ tiếp có vẫn vào TextEdit không; (c) thanh menu còn ghi "TextEdit" không.
Chặn: m0-p03-cook (báo cáo ngày 1), m0-p03-review, Phase 6
Seen: [x]
Answer: 2026-11-22 21:52 (file) đã xong, proble hiện thời gian

## D9 · Phase 3 (C ngày 1) · ANSWERED · 2026-11-22 21:52
Cảm ơn, widget hiện thời gian nghĩa là A đạt ngày 1. Còn thiếu kết quả Phần C (TextEdit, xem file hướng dẫn D7): khi panel "Probe panel" hiện ra, chữ bạn gõ tiếp có còn vào TextEdit không?
- A: Vẫn vào TextEdit, thanh menu vẫn ghi TextEdit (panel không cướp focus).
- B: Chữ bị mất hoặc nhảy sang panel / thanh menu đổi tên (panel cướp focus).
- C: Chưa làm Phần C.
Chặn: m0-p03-cook (báo cáo ngày 1), m0-p03-review, Phase 6
Seen: [x]
Answer: 2026-11-22 21:55 (file) panel có hiện sau 10s

## D10 · Phase 3 (C ngày 1) · ANSWERED · 2026-11-22 21:55
Panel hiện sau 10 giây (đã ghi). Câu còn lại: lúc panel hiện, bạn đang gõ trong TextEdit thì chữ gõ tiếp có còn vào TextEdit không?
- A: Vẫn vào TextEdit, thanh menu vẫn ghi TextEdit.
- B: Chữ bị mất hoặc nhảy sang panel, hoặc thanh menu đổi tên.
- C: Lúc đó không gõ; để mình thử lại rồi báo.
Chặn: m0-p03-cook (báo cáo ngày 1), m0-p03-review, Phase 6
Seen: [ ]
Answer: 2026-11-22 21:56 (dialog) Vẫn vào TextEdit
