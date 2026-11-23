# D7: Cách thử widget (A) và panel (C)

App "WidgetProbe" đã cài lúc 21:47 và đang chạy. Đừng thoát app: nó cần chạy liên tục 7 ngày (đến 30/11).

## Phần A: widget có đọc được dữ liệu app ghi không

1. Nhìn góc trên bên phải màn hình, trên thanh menu có chữ **Probe**.
   Nếu không thấy: Finder → Applications → mở **WidgetProbe**.
2. Nếu macOS hiện hộp thoại xin quyền (truy cập dữ liệu của app khác), bấm **Cho phép**
   và chép lại nguyên văn câu hỏi.
3. Bấm chuột phải vào chỗ trống trên desktop → chọn **Edit Widgets…** (Sửa tiện ích).
4. Gõ **Probe** vào ô tìm kiếm, kéo widget **Probe** ra desktop, bấm **Done**.
5. Lúc này widget hiện "App Group: lỗi" là bình thường (app chưa ghi gì).
6. Bấm **Probe** trên thanh menu → chọn **Ghi dữ liệu**.
7. Chờ tối đa 1 phút rồi nhìn widget.

Báo lại:
- (a) widget hiện **mốc thời gian** (vd. 2026-11-22T21:50:12+07:00) hay vẫn **"App Group: lỗi"**;
- (b) khoảng bao lâu sau khi bấm thì widget đổi;
- (c) bước 2 có hộp thoại không, có thì ghi nguyên văn;
- (d) trong menu Probe, dòng "App Group: …" ghi gì.

## Phần C: panel có cướp chỗ gõ của TextEdit không

1. Mở **TextEdit**, tạo văn bản mới.
2. Bấm **Probe** trên thanh menu → chọn **Mở panel sau 10 giây**.
3. Ngay lập tức bấm vào văn bản TextEdit và gõ liên tục (vd. "aaaaaa…") khoảng 15 giây.
4. Sau ~10 giây, một panel nhỏ "Probe panel" hiện giữa màn hình. Cứ gõ tiếp, **không bấm vào panel**.
5. Xong thì đóng panel bằng nút x.

Báo lại:
- (a) panel có hiện không;
- (b) sau khi panel hiện, chữ gõ tiếp **vẫn vào TextEdit** hay bị mất / đi chỗ khác;
- (c) thanh menu trên cùng còn ghi **TextEdit** không.

## Cách trả lời

Ghi vào dòng `Answer:` của D7 trong file ledger, hoặc nhắn trong chat, ví dụ:

`D7: A(a) hiện mốc thời gian, (b) ~5 giây, (c) không có hộp thoại, (d) App Group: OK; C(a) có, (b) vẫn vào TextEdit, (c) còn ghi TextEdit`
