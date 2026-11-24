# Follow-ups — M2 menu bar app

Deferred until after experiment A's day-8 check (2026-11-30), by operator decision "Cook ngay, chưa ký/cài":
- Phase 1 checks that need signing or running the app: signed Debug build with `-allowProvisioningUpdates`,
  `codesign -d --entitlements -` showing sandbox, network client and App Group; menu bar icon without Dock icon;
  settings save token to Keychain and it survives restart.
- Phase 5 manual focus check (popup while typing in TextEdit) and any other check that runs the app.
- Choose the A branch (plan.md "Nhánh theo kết quả thử nghiệm") and adjust `project.yml` / `StoreLocation` if A fails.
- From the Phase 1 review (for Phase 6): KeychainTokenStore uses the file-based keychain (no
  kSecUseDataProtectionKeychain); if weekly rebuilds are needed, check whether macOS prompts for Keychain access
  after each re-sign. `containerURL` on macOS may return a path even without the entitlement. Check by eye that
  `NSApp.activate()` brings the settings window to the front.

## Phase 3 (sync engine) — deferred to Phase 6
- Live Realtime join + INSERT signal: `supabase projects api-keys` timed out once (likely needs login); the publishable key is needed (Settings field). Opt-in test liveJoinAndInsert (OSWIDGET_LIVE_REALTIME=1, OSWIDGET_SUPABASE_URL/KEY).
- publish → realtime.state joined + sync.applied in log stream; Wi-Fi off 1 min → immediate round; lsof one WebSocket; sleep/wake reopens socket; sandbox network.client allows WebSocket/NWPathMonitor in signed build.
- Known limit: token-only change in Settings waits for next trigger (poll ≤ 5 min).
- Realtime: Supabase may report a postgres_changes subscription error as a `system` message after a successful join; the client ignores it, so the log shows joined but no signals (5-minute poll still catches up). Check in Phase 6.
- Known small race: stop() then start() back to back may clear the new socket reference (no leak). Low priority.

## Phase 4/5 — deferred to Phase 6
- Link click inside a card (opens only that link, marks read); .transient popover toggle when clicking the icon with the list open; list fixed 480 pt height.
- Popup: focus stays in TextEdit, 30 s countdown with hover pause, "+N" opens list, suppression reasons in log, full-screen display, panel sizing after image load (372 pt width).

## Việc ngày 2026-11-30 (kiểm A ngày 8) — operator quyết định 2026-11-23 22:35 không chờ (D1)
Nguyên văn: "chúng ta không thể chời tới ngày 30/11 để tiếp tục, để note lại đó đến ngày sẽ kiểm tra lại, cứ move on".
- Mở /Applications/WidgetProbe.app và widget "Probe": app còn chạy không, widget còn đọc App Group không. Ghi vào
  plans/261122-0754-m0-kiem-chung-worker-rust/reports/a-c-results.md và hàng A của docs/roadmap.md.
- Đồng thời kiểm OSWidget (cài 2026-11-23/24): còn mở được, còn đọc store.json trong group container.
- Nếu A đạt: không đổi gì. Nếu A trượt vì app không mở sau ~7 ngày: thêm scripts/build-install-macos.sh (build
  lại hằng tuần, câu hỏi 4) và ghi chu kỳ vào architecture §9. Nếu A trượt vì App Group: bỏ entitlement
  application-groups, StoreLocation dùng Application Support (plan.md, bảng "Nhánh theo kết quả thử nghiệm").
- Lưu ý: OSWidget dùng chung group container 22LZWPB3XL.os-widget với WidgetProbe (file riêng store.json), ký
  cùng chứng chỉ Apple Development hiện có; nếu A trượt cần xét OSWidget có ảnh hưởng không.

## Phase 6 — hoãn
- Tiêu chí 4 (PRD §10.4, mất mạng + publish 3 mục từ máy khác): hoãn, operator hiện chỉ có MacBook (2026-11-23 ~22:45). Chạy `scripts/acceptance-menu-bar.sh 4` khi có Mac mini hoặc máy khác chạy CLI.
- Lỗi phát hiện khi cấu hình: không paste được vào ô Cài đặt (app LSUIElement không có menu Edit) — đang sửa ở p06.

## Phase 6 — quan sát khi chạy app (cook, 2026-11-23 ~23:00)
- "+N" trên popup tăng dần khi popup đang mở và vẫn đếm mục đã bị xoá trong lúc đó (có thể hiện "+4" khi không còn mục nào). Do thiết kế PopupPolicy.merge; review Phase 6 quyết định sửa nhỏ hay ghi nhận.
- Đổi cấu hình: socket Realtime cũ dừng và join lại trong 1 s (log có send_failed) — vô hại.
- Khoá publishable trong Keychain lần đầu chỉ 6 ký tự (dán ở prompt `security` không ăn) → D3 nhập lại.
- Danh sách mục (popover) không tự đóng khi bấm sang TextEdit (operator, D4: "không", 2026-11-24). Cook ghi nguyên nhân nghi ngờ; review Phase 6 quyết định sửa hay để sau.

## Sau Phase 6 (2026-11-24, M2 merge 307f115, trạng thái 05df373; plan M2 để in-progress)
- Danh sách không tự đóng: đã sửa d9e8118 (nguyên nhân chứng minh: `list.shown active=false`), operator kiểm lại D5 "1 đạt / 2 đạt / 3 đạt".
- "+N" cộng dồn và đếm mục đã xoá (PopupPolicy.merge): để làm sau, cần đổi hợp đồng PopupPolicy/PopupController (giữ tập id đang hiện).
- Chờ operator: mục 10 đăng xuất/đăng nhập (tự chạy, không icon Dock); mục 11 ngủ qua đêm; tiêu chí 4 (PRD §10.4) khi có máy thứ hai — xong thì đóng plan M2.
- 2026-11-30: kiểm A ngày 8 (có thể đổi nhánh ký/cài).
- main chưa push lên origin.

## Đóng M2 (2026-11-24 09:52)
Operator, nguyên văn: "đánh dấu tiêu chí 4 lại khi nào có máy thứ 2 sẽ test, xem như M2 xong, push và chuẩn bị chuuyeenr sang M3".
- Plan M2 `status: completed`; tiêu chí 4 ghi hoãn trong plan.md (Done means 3), phase-06, acceptance.md, roadmap (Giai đoạn 2 và một dòng ở Giai đoạn 5).
- Còn mở sau khi đóng M2: tiêu chí 4 khi có máy thứ hai; mục 10, 11 của checklist; kiểm A ngày 8 (2026-11-30); "+N" của popup.
