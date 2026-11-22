# Roadmap: os-widget

Cập nhật: 2026-11-22. Yêu cầu nằm ở [prd.md](prd.md), thiết kế ở [architecture.md](architecture.md).

Roadmap xếp theo thứ tự và điều kiện hoàn thành, không gắn ngày. Mỗi giai đoạn kết thúc bằng một thứ chạy được và kiểm chứng được.

## Tổng quan

| Giai đoạn | Kết quả | Phụ thuộc |
|---|---|---|
| 0. Kiểm chứng | Biết chắc bốn giả định rủi ro nhất đúng hay sai | Không |
| 1. Server | Publish và đọc được mục qua API thật | 0 (chỉ thử nghiệm D) |
| 2. App thanh menu | Mục mới hiện ở popup, đồng bộ đã đọc và xoá | 1; thử nghiệm A, B, C |
| 3. Widget | Mục mới nhất nằm đầu widget trên desktop | 2; thử nghiệm A, B |
| 4. Từ vựng | Thẻ từ vựng đầy đủ, tự gửi theo chu kỳ | 2 |
| 5. Hoàn thiện | Dùng hằng ngày trên cả hai máy | 3, 4 |
| Sau này | iPhone, Windows | 5 |

Giai đoạn 3 và 4 độc lập với nhau, làm theo thứ tự nào cũng được.

## Giai đoạn 0: Kiểm chứng

Mục đích là trả lời bốn câu hỏi có thể làm đổi thiết kế, bằng mã thử nghiệm bỏ đi được.

| Thử nghiệm | Câu hỏi | Nếu thất bại |
|---|---|---|
| A. App và widget với tài khoản miễn phí | App Groups có dùng được không? Sau 7 ngày app có còn chạy không? | Widget lấy dữ liệu qua localhost; cân nhắc tài khoản trả phí. |
| B. Độ trễ widget | App nền yêu cầu làm mới thì widget cập nhật sau bao lâu, được bao nhiêu lần mỗi ngày? | Thay widget bằng cửa sổ SwiftUI ở tầng desktop. |
| C. Popup tự mở | Popup tự mở có cướp focus khi đang gõ ở app khác không? | Dùng panel không kích hoạt. |
| D. Worker Rust với Supabase | Worker Rust có đọc, ghi Supabase qua REST trong 10 ms CPU không? | Viết Worker bằng TypeScript. |

**Hoàn thành khi:** mỗi câu hỏi có câu trả lời kèm số đo, và architecture.md được cập nhật theo kết quả. Giai đoạn 1 chỉ cần kết quả D. A và B phải có kết quả trước Giai đoạn 2 và 3; C phải có kết quả trước Giai đoạn 2. Thử nghiệm A cần một tuần chờ để biết về hạn 7 ngày.

### Kết quả

| Thử nghiệm | Trạng thái |
|---|---|
| D | Xong. Worker Rust đọc, ghi Supabase qua REST được, nhưng trượt ngưỡng p99 ≤ 5 ms đặt ra: `POST /items` p50 2 ms, p99 11 ms; `GET /events` p50 3 ms, p99 7 ms (hai lần đo, 140–147 request mỗi endpoint). Request trúng isolate mới tốn 16–21 ms, vượt hạn mức 10 ms nhưng không bị chặn. Dung lượng 563.08 KiB chưa nén, dưới hạn mức 64 MiB. Chủ dự án quyết định giữ Rust và chấp nhận rủi ro (architecture.md mục 9). |
| A | Đang chạy. App thử nghiệm cài ngày 2026-11-22, ký bằng Personal Team miễn phí, không có provisioning profile. Ngày 1 đạt: widget đọc được dữ liệu app ghi qua App Group. Kiểm ngày 8 vào 2026-11-30. |
| B | Chưa đo. Đo bằng app thử nghiệm A trước Giai đoạn 2. |
| C | Ngày 1 đạt: panel không kích hoạt tự mở mà không lấy focus khỏi TextEdit đang gõ. |

## Giai đoạn 1: Server

- Tạo bảng `items`, `events`, trigger ghi sự kiện và chính sách RLS trên Supabase.
- Crate `envelope` với ba loại: `notification`, `vocab`, `generic`.
- Worker với năm endpoint và hai token. `GET /events` giới hạn số sự kiện mỗi trang, vì đọc 159 sự kiện một lần đã tốn 15–19 ms CPU.
- CLI publish dùng lại crate `envelope`.
- Tác vụ định kỳ dọn mục hết hạn, mục đã xoá và sự kiện cũ.

**Hoàn thành khi:**

1. CLI publish một mục và `GET /events` trả về mục đó.
2. Envelope sai định dạng bị từ chối với thông báo nêu rõ trường sai.
3. Publish hai lần cùng `dedupe_key` chỉ tạo một mục.
4. Đánh dấu đã đọc và xoá sinh đúng sự kiện.
5. Request thiếu token hoặc dùng sai loại token bị từ chối.
6. Khoá anon đọc được `events` nhưng không đọc được `items`.

## Giai đoạn 2: App thanh menu

- App agent với icon thanh menu, chạy khi đăng nhập.
- Sync engine: tín hiệu Realtime, fetch theo cursor, poll dự phòng, bắt kịp sau khi ngủ hoặc mất mạng.
- Kho cục bộ và hàng đợi thao tác.
- Popup tự mở, tự đóng sau 30 giây; gộp nhiều mục tới cùng lúc; bật tắt theo loại nội dung và chế độ yên lặng.
- Danh sách mục, dấu báo chưa đọc, đã đọc và xoá.
- View cho `notification`, `generic` và hiển thị dự phòng cho loại lạ.

**Hoàn thành khi:** đạt các tiêu chí 1, 3, 4 và 6 ở mục 10 của PRD, và popup không cướp focus khi đang gõ.

## Giai đoạn 3: Widget

- Widget extension đọc kho dùng chung, cỡ vừa và cỡ lớn.
- Mục mới nhất nằm trên cùng; bố cục rút gọn cho từng loại.
- Nút đã đọc và xoá ngay trong widget.
- App chỉ yêu cầu làm mới khi nội dung widget đổi.

**Hoàn thành khi:** đạt tiêu chí 2 ở mục 10 của PRD; thao tác đã đọc trong widget đồng bộ sang máy kia; số lần làm mới trong một ngày dùng thật nằm dưới mức đo được ở thử nghiệm B.

## Giai đoạn 4: Từ vựng

- View `vocab` đầy đủ ở popup và danh sách; bố cục rút gọn ở widget.
- Phát âm bằng bộ đọc của hệ thống, hoặc `audio_url` nếu có.
- Bảng `vocab_words` và `settings`; endpoint nạp từ.
- Lệnh `ingest` nạp từ một API từ điển công khai trước, sau đó từ sách.
- Cron Trigger gửi một từ chưa gửi theo chu kỳ, mặc định 1 giờ, chỉnh bằng bảng `settings`.

**Hoàn thành khi:**

1. Đạt tiêu chí 5 ở mục 10 của PRD.
2. Nạp một danh sách từ qua API từ điển tạo ra các mục đủ trường; nạp lại không tạo bản trùng.
3. Nạp một cuốn sách tạo ra các từ kèm câu ngữ cảnh lấy từ sách.
4. Đổi chu kỳ trong `settings` có hiệu lực mà không phải deploy lại.
5. Khi hết từ, hệ thống dừng hoặc quay vòng đúng theo cấu hình.

Nạp từ API làm trước vì đơn giản hơn và đủ để có bộ từ dùng được; nạp từ sách cần thêm bước tách từ và chọn từ đáng học. Còn phải chọn API từ điển và định dạng sách (mục 11 của PRD).

## Giai đoạn 5: Hoàn thiện

- Cài và chạy trên cả MacBook và Mac mini.
- App báo rõ khi server không phản hồi hoặc token sai.
- Tích hợp ba bên gửi thật: nhóm agent blog, Hermes, bộ sinh từ vựng.
- Hướng dẫn cài đặt, cấu hình token và cách thêm một loại nội dung mới.
- Theo dõi mức dùng Cloudflare và Supabase trong một tuần.

**Hoàn thành khi:** đạt đủ bảy tiêu chí ở mục 10 của PRD trên cả hai máy.

## Sau này

| Hạng mục | Việc chính | Điều kiện trước |
|---|---|---|
| iPhone | App và widget iOS dùng lại package dùng chung; thêm đường push của Apple ở server. | Tài khoản Apple trả phí. |
| Windows | Client khay hệ thống và widget provider chuyển envelope sang Adaptive Cards. | Quyết định chọn C# với WinUI 3 hay Tauri. |
| Loại nội dung mới | Thêm `kind` theo quy tắc ở mục 3.3 của architecture.md. | Không. |

## Việc cần quyết định trước khi bắt đầu

1. API từ điển và định dạng sách dùng để nạp bộ từ (ảnh hưởng giai đoạn 4, không chặn các giai đoạn trước).
2. Thời hạn tồn tại mặc định của một mục khi bên gửi không đặt `ttl`: đang tạm đặt 30 ngày, chờ xác nhận (ảnh hưởng giai đoạn 1).

Đã chốt: hành vi popup theo FR-6 đến FR-10c của PRD, thời gian popup hiển thị là 30 giây.
