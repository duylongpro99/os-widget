# PRD: os-widget

Cập nhật: 2026-11-22. Trạng thái: bản nháp đầu tiên, chưa triển khai.

Tài liệu liên quan: [architecture.md](architecture.md), [roadmap.md](roadmap.md).

## 1. Vấn đề

Nhiều nguồn tự động (nhóm agent viết blog, cron từ vựng, agent Hermes ở máy khác) tạo ra nội dung mà tôi muốn thấy ngay trên máy đang làm việc. Hiện không có một chỗ chung để các nguồn đó gửi vào, và không có một bề mặt nào trên macOS hiển thị chúng một cách gọn, đẹp và nhất quán.

## 2. Mục tiêu

os-widget là một kênh cá nhân một chiều: bất kỳ nguồn nào cũng gửi được một mục nội dung lên server bằng một lệnh, và mục đó hiện trên các máy của tôi qua icon trên thanh menu và widget trên desktop.

- Một lệnh publish duy nhất cho mọi nguồn gửi.
- Nội dung mới hiện trên máy trong vài giây khi app đang chạy và có mạng.
- Mỗi loại nội dung lặp lại có giao diện riêng được thiết kế kỹ; loại mới chưa biết vẫn hiển thị được mà không phải build lại app.
- Chạy hoàn toàn trên các gói miễn phí (Apple, Cloudflare, Supabase).

## 3. Ngoài phạm vi

- Nhiều người dùng, tài khoản, phân quyền.
- Phân phối cho người khác hoặc đưa lên App Store.
- Trả lời hoặc trò chuyện ngược lại với agent. Tương tác ngược chỉ gồm đánh dấu đã đọc và xoá.
- Bản iPhone và bản Windows trong giai đoạn đầu. Kiến trúc phải không chặn hai hướng này (xem mục 9).
- Hiển thị HTML tuỳ ý hoặc chạy mã do bên gửi cung cấp.

## 4. Người dùng

Một người dùng duy nhất, dùng một MacBook và một Mac mini (macOS 26), tự build app bằng Xcode với tài khoản Apple miễn phí. Bên gửi là các agent và cron job do chính người dùng vận hành.

## 5. Kịch bản

| Mã | Kịch bản | Loại nội dung |
|---|---|---|
| S1 | Nhóm agent viết blog xong một bài, gửi một thông báo; app hiển thị thông báo kèm liên kết tới bài. | `notification` |
| S2 | Server lấy một từ từ bộ từ tự xây (nạp từ sách hoặc API công khai) và gửi theo chu kỳ (mặc định 1 giờ, tuỳ chỉnh được) gồm cách đọc, câu ví dụ, ngữ cảnh, từ đồng nghĩa và trái nghĩa, phát âm. | `vocab` |
| S3 | Hermes, agent ở máy khác, gửi một thông báo; app hiển thị. | `notification` |
| S4 | Một nguồn mới chưa có giao diện riêng gửi nội dung có cấu trúc tự do. | `generic` |

## 6. Yêu cầu chức năng

### Gửi nội dung

- **FR-1.** Bên gửi publish một mục bằng một HTTP request có token, hoặc bằng CLI bọc request đó.
- **FR-2.** Server từ chối mục sai định dạng và trả về lỗi nêu rõ trường sai. Mọi dữ liệu thô phải được bên gửi chuẩn hoá về định dạng envelope trước khi gửi.
- **FR-3.** Mọi mục đều có `title` và `summary` dạng text thuần, dùng làm hiển thị dự phòng ở mọi nơi.
- **FR-4.** Gửi lại cùng một mục (cùng `dedupe_key`) không tạo mục trùng.

### Thanh menu

- **FR-5.** App có một icon trên thanh menu, không có icon Dock, tự chạy khi đăng nhập.
- **FR-6.** Khi có mục mới, popup dưới icon tự mở và hiện mục đó, bất kể desktop có đang bị che hay không. Popup tự đóng sau 30 giây hoặc khi người dùng bấm nút đóng. Bộ đếm dừng khi chuột đang nằm trong popup.
- **FR-7.** Popup tự mở không cướp focus bàn phím của app đang dùng và mặc định không phát âm thanh.
- **FR-8.** Không bao giờ có hai popup cùng lúc. Mục mới tới khi popup đang mở thì thay nội dung popup và đếm lại 30 giây. Nhiều mục tới cùng lúc (ví dụ sau khi máy thức dậy) mở một popup hiện mục mới nhất kèm số mục còn lại.
- **FR-9.** Bấm icon mở danh sách các mục, mục mới nhất ở trên cùng, phân biệt rõ đã đọc và chưa đọc. Icon hiện dấu báo khi còn mục chưa đọc.
- **FR-10.** Mục có `priority: low` không tự mở popup, chỉ cập nhật dấu báo và danh sách.
- **FR-10a.** Popup tự đóng không tính là đã đọc: mục vẫn chưa đọc và dấu báo vẫn còn. Bấm vào thẻ thì đánh dấu đã đọc và mở liên kết nếu có.
- **FR-10b.** Khi danh sách đang mở, mục mới chèn lên đầu danh sách và được làm nổi bật, không mở popup riêng.
- **FR-10c.** Người dùng bật, tắt việc tự mở popup theo từng loại nội dung (ví dụ tắt cho `vocab` nếu popup mỗi giờ gây phiền), và có chế độ yên lặng tạm thời tắt mọi popup. Khi popup bị tắt, mục vẫn vào danh sách, widget và dấu báo.

### Widget desktop

- **FR-11.** Widget hiện các mục mới nhất, mục mới nhất nằm trên cùng.
- **FR-12.** Widget hiện được phần rút gọn của mọi loại nội dung, tối thiểu là `title` và `summary`.
- **FR-13.** Có ít nhất hai cỡ widget: cỡ vừa (vài mục) và cỡ lớn (nhiều mục hơn hoặc một thẻ từ vựng đầy đủ hơn).

### Hiển thị nội dung

- **FR-14.** Loại `notification`: tiêu đề, nội dung ngắn, nguồn, thời gian, liên kết mở bằng trình duyệt.
- **FR-15.** Loại `vocab`: từ, phiên âm, từ loại, nghĩa, câu ví dụ, ngữ cảnh sử dụng, từ đồng nghĩa và trái nghĩa, nút phát âm.
- **FR-16.** Loại `generic`: hiển thị danh sách block (tiêu đề, đoạn văn markdown, cặp khoá/giá trị, danh sách, ảnh, mã, liên kết).
- **FR-17.** Loại chưa biết: hiển thị `title` và `summary`, không báo lỗi.

### Bộ từ vựng

- **FR-24.** Hệ thống có một bộ từ riêng lưu trên server. Mỗi từ được chuẩn hoá về đúng các trường của loại `vocab` trước khi lưu.
- **FR-25.** Bộ từ được nạp từ hai loại nguồn: sách (văn bản) và API từ điển công khai. Nạp lại cùng một từ không tạo bản trùng.
- **FR-26.** Theo chu kỳ (mặc định 1 giờ, chỉnh được bằng cấu hình), server chọn một từ chưa gửi trong bộ từ và publish thành một mục `vocab`.
- **FR-27.** Khi bộ từ đã gửi hết, server không gửi mục rỗng hoặc lỗi; hành vi tiếp theo (dừng hay quay vòng) là một cấu hình.

### Đã đọc và xoá

- **FR-18.** Người dùng đánh dấu đã đọc hoặc xoá một mục từ popup, danh sách và widget.
- **FR-19.** Trạng thái đã đọc và xoá đồng bộ giữa mọi thiết bị. Trạng thái gắn với mục, không gắn với thiết bị.
- **FR-20.** Thao tác khi mất mạng được giữ lại và gửi đi khi có mạng.

### Đồng bộ

- **FR-21.** App nhận tín hiệu đẩy khi có thay đổi, và tự poll theo chu kỳ để dự phòng.
- **FR-22.** Sau khi mất kết nối hoặc máy ngủ, app tự lấy lại mọi thay đổi đã bỏ lỡ, không mất và không trùng mục.
- **FR-23.** Mục hết hạn (`ttl`) tự biến mất khỏi mọi bề mặt.

## 7. Yêu cầu phi chức năng

| Mã | Yêu cầu |
|---|---|
| NFR-1 | Mục mới hiện ở popup trong vòng 5 giây khi app đang chạy và có mạng. |
| NFR-2 | Widget có thể trễ hơn popup. Mức trễ chấp nhận được sẽ chốt sau khi đo (xem roadmap, giai đoạn 0). |
| NFR-3 | Toàn bộ hệ thống nằm trong hạn mức miễn phí của Cloudflare Workers và Supabase. |
| NFR-4 | Mọi request đi qua HTTPS và có token. Token publish và token của app tách riêng. |
| NFR-5 | App chạy nền dùng ít tài nguyên: không poll dày hơn mức cần, không giữ nhiều hơn một kết nối realtime. |
| NFR-6 | Thêm một loại nội dung mới chỉ cần thêm một schema và một view, không sửa phần đồng bộ. |

## 8. Ràng buộc

- **Tài khoản Apple miễn phí.** App chỉ build và chạy trên máy của chính người dùng; profile ký có thể hết hạn sau khoảng 7 ngày và cần build lại. Khả năng chia sẻ dữ liệu giữa app và widget bằng App Groups với tài khoản miễn phí chưa được xác nhận.
- **WidgetKit.** Widget không cập nhật tức thì: hệ thống giới hạn số lần làm mới mỗi ngày (ước tính không chính thức là 40 đến 70 lần). Widget không thể nổi lên trên cửa sổ khác.
- **Supabase miễn phí.** Project bị tạm dừng sau khoảng một tuần ít hoạt động; tối đa 2 project hoạt động.
- **Cloudflare Workers miễn phí.** 100.000 request mỗi ngày, 10 ms CPU mỗi request.

## 9. Hướng mở rộng cần giữ đường

- **iPhone.** Dùng lại mã Swift và widget. Cần push của Apple, nhiều khả năng đòi tài khoản trả phí.
- **Windows.** Cần một client viết riêng. Widget Windows 11 dùng Adaptive Cards, nên block của loại `generic` chỉ gồm những thứ ánh xạ được sang Adaptive Cards.
- Vì hai hướng trên, định dạng envelope và API server không được phụ thuộc vào SwiftUI hay bất kỳ nền tảng client nào.

## 10. Tiêu chí hoàn thành bản đầu

1. Một lệnh publish từ máy khác làm popup hiện trên MacBook trong 5 giây.
2. Cùng mục đó xuất hiện ở đầu widget và ở đầu danh sách.
3. Đánh dấu đã đọc trên MacBook làm mục đó thành đã đọc trên Mac mini.
4. Tắt mạng, publish ba mục, bật mạng lại: cả ba mục hiện đủ, không trùng.
5. Một thẻ từ vựng hiện đủ các trường ở FR-15 và phát âm được.
6. Một mục có `kind` lạ vẫn hiện `title` và `summary`.
7. Sau một tuần chạy, mức dùng Cloudflare và Supabase vẫn trong hạn mức miễn phí.

## 11. Câu hỏi còn mở

1. Đã chốt (2026-11-22): tự xây bộ từ, nạp từ sách hoặc API công khai (FR-24 đến FR-27). Còn mở: dùng API từ điển nào, và sách ở định dạng gì (PDF, EPUB, text).
2. Đã chốt (2026-11-22): hành vi popup theo FR-6 đến FR-10c. Popup luôn mở cho mục không phải `low`, không dò trạng thái desktop.
3. Thời gian popup hiển thị là 30 giây (đã chốt). Thời hạn tồn tại mặc định của một mục khi bên gửi không đặt `ttl` đang tạm đặt là 30 ngày và cần xác nhận; nếu đặt 30 giây thì mục sẽ biến mất khỏi widget và danh sách ngay sau khi popup đóng.
