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
