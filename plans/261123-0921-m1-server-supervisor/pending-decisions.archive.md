# Answered decisions

## D1 · M1 Phase 1 và 5 · ANSWERED · 2026-11-23 09:22
Plan M1 có các thao tác thật: Phase 1 đẩy migration mới (quyền anon, Realtime, pg_cron dọn dữ liệu) lên Supabase gykrhmpliphrcpiryzuq; Phase 5 đặt hai secret PUBLISH_TOKEN/CLIENT_TOKEN, deploy lại Worker os-widget.longdaobk17.workers.dev rồi xoá SPIKE_TOKEN. Cho phép không, và lưu hai token ở đâu?
- A (đề xuất): Cho phép đúng các thao tác trên; token sinh bằng openssl rand -hex 32, lưu vào macOS Keychain (service os-widget-publish-token và os-widget-client-token, giống SPIKE_TOKEN ở M0), pipe thẳng vào wrangler secret put, không ghi ra file.
- B: Cho phép, nhưng tôi tự lưu token vào trình quản lý mật khẩu của tôi (phiên Phase 5 dừng chờ tôi).
- C: Chưa cho phép thao tác thật; chỉ làm và kiểm cục bộ.
Chặn: bước db push của m1-server-p01-cook; toàn bộ Phase 5
Seen: [ ]
Answer: 2026-11-23 09:29 (dialog) Cho phép, Keychain (Đề xuất)

## D2 · M1 Phase 1 (Docker) · ANSWERED · 2026-11-23 09:30
Ổ đĩa VM của Docker Desktop đầy (58.4G dùng, 0 trống) nên supabase start lỗi "No space left on device"; volume floci-aws-ec2-volumes chiếm 176GB, build cache 5.4GB (dựng lại được). Image Supabase đã có sẵn, chỉ cần vài GB. Xử lý thế nào?
- A (đề xuất): Cho phiên cook chạy docker builder prune -f (xoá ~5.4GB build cache, không đụng image, container hay volume).
- B: Tôi tự tăng Disk usage limit trong Docker Desktop → Settings → Resources (vd. lên 128GB), báo lại khi xong.
- C: Tôi tự dọn volume cũ (vd. floci-aws-ec2-volumes 176GB), báo lại khi xong.
- D: Bỏ kiểm cục bộ, chỉ kiểm trên project sau db push (rủi ro: lỗi migration lộ ra trên project thật).
Chặn: m1-server-p01-cook (kiểm cục bộ, rồi db push)
Seen: [ ]
Answer: 2026-11-23 09:34 (dialog) Tôi dọn volume cũ

## D3 · M1 Phase 5 (Keychain) · ANSWERED · 2026-11-23 11:46
macOS đang hiện hộp thoại Keychain (SecurityAgent) hỏi có cho Supabase CLI đọc access token đăng nhập của chính nó không. Lệnh `supabase projects api-keys` của m1-server-p05-cook (pid 6149) đang chờ hộp thoại này để lấy khoá publishable (sb_publishable_…) cho tiêu chí 6. Xử lý thế nào?
- A (đề xuất): Bạn bấm "Allow" (hoặc "Always Allow") trên hộp thoại. CLI chỉ đọc token đăng nhập của nó như ở các phase trước; khoá publishable vốn công khai và không được ghi ra file.
- B: Bấm "Deny"; bạn tự lấy khoá publishable từ dashboard Supabase và báo lại (phiên Phase 5 chờ).
Chặn: script nghiệm thu của m1-server-p05-cook (tiêu chí 6 và lần chạy đầy đủ)
Seen: [ ]
Answer: 2026-11-23 11:50 (dialog) Tôi bấm Allow (Đề xuất)

## D4 · M1 Phase 5 (secret key) · ANSWERED · 2026-11-23 11:55
Khi kiểm loại khoá, phiên m1-server-p05-cook in 15 ký tự đầu của mỗi khoá API Supabase vào transcript của nó (trên máy này, không vào repo hay báo cáo). Với khoá sb_secret_ (service role, Worker đang dùng) là "sb_secret_" + 5 ký tự. Có xoay khoá không?
- A (đề xuất): Không xoay. 5 ký tự của một khoá ngẫu nhiên dài không đủ để dùng hay đoán khoá, và transcript chỉ nằm trên máy bạn. Ghi lại vào follow-ups.
- B: Xoay khoá: tạo khoá secret mới trên Supabase, pipe vào `wrangler secret put SUPABASE_SERVICE_ROLE_KEY`, kiểm Worker, rồi thu hồi khoá cũ (một phiên mới làm, sau khi review Phase 5 merge).
Chặn: không chặn merge; chỉ quyết định có thêm phiên xoay khoá hay không
Seen: [ ]
Answer: 2026-11-23 13:29 (dialog) Xoay khoá sau khi merge
