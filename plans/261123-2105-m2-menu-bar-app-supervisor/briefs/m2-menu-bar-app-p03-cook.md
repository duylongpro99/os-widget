# Brief: m2-menu-bar-app-p03-cook

You are session "m2-menu-bar-app-p03-cook". Your only job: implement Phase 3 (sync engine) of the M2 plan with
`/ak-cook`, on its own branch and worktree, without signing, installing or running the app. You do NOT merge:
a separate session "m2-menu-bar-app-p03-review" will review and merge. The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md (file-ownership table), phase-03-sync-engine.md, docs/architecture.md
  §3–§7 as the phase cites them, the current code under apps/macos/ (Phase 1 hooks in App/, Phase 2 Model/ and
  Store/ in OSWidgetKit), plans/reports/review-261123-m2-p01.md and review-261123-m2-p02.md.
- State: main is at 3db956b (Phase 2 merged 58f043e). `cd apps/macos/OSWidgetKit && swift test` → 42 tests
  in 5 suites pass. Unsigned xcodebuild succeeds. `cargo test --workspace` passes.
- Phase 2 public API (use it, do not change it): ItemStore apply(events:) -> [Item], replaceAll(items:seq:),
  announce(_:), announcement (Announcement serial/items), markRead/markUnread/delete(_:), complete(_:outcome:),
  queue, cursor, lastFullSyncAt, visibleItems, unreadCount, item(id:), popupSettings, setPopup(kind:enabled:),
  setQuietMode(_:); PendingAction.outcome(for: Int?) -> QueueOutcome; Item, ItemContent, Block, ServerEvent.
  Calling markRead/markUnread/delete on a deleted item does nothing.
- Phase 1 hook signatures are fixed (AppDelegate.swift and AppEnvironment.swift are owned by nobody now):
  SyncWiring.start(env:), MenuBarController(env:) with anchorRect() -> NSRect? and isListOpen,
  PopupController(env:anchor:isListOpen:). If you need to change one, stop and SendMessage m0-supervisor.
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Verify only with `swift test` and
  unsigned builds. No Apple-account signing, no `-allowProvisioningUpdates`, no install, do not launch the app,
  no access to ~/Library/Group Containers/22LZWPB3XL.os-widget, never touch WidgetProbe, until 2026-11-30.
  The phase's manual checks that need the running app are deferred to Phase 6: list them in your report as
  "hoãn tới sau 30/11".
- Running in parallel (same base 3db956b): m2-menu-bar-app-p03-cook (sync engine), m2-menu-bar-app-p04-cook
  (menu bar, list, cards), m2-menu-bar-app-p05-cook (popup). Write only your own files from the ownership table.
  Do not edit Package.swift, project.yml, AppDelegate.swift, AppEnvironment.swift or another phase's files; if
  you think you must, SendMessage m0-supervisor first.

Work
1. `git worktree add ../os-widget-macos-sync -b macos-sync-engine` from main; work only there.
2. Implement phase-03-sync-engine.md Requirements, Files and the tests it lists, exactly.
   - Run the queue send and the event fetch sequentially inside one sync round (the Phase 2 reviewer noted that a
     GET /events racing a PATCH can briefly overwrite a read state until the next fetch).
   - Live checks without the app (allowed, limited): you may add an opt-in integration test that is skipped
     unless an env var is set (e.g. OSWIDGET_LIVE_REALTIME=1), connecting RealtimeSignal to
     https://gykrhmpliphrcpiryzuq.supabase.co with the publishable key and waiting for one INSERT on events.
     The publishable key is not in the Keychain. You may try once `supabase projects api-keys --project-ref
     gykrhmpliphrcpiryzuq` to read it into a variable without printing it; if that shows a dialog, needs login
     or fails, do not retry: skip the live Realtime check, mark it deferred, and say so. To trigger the INSERT
     you may publish at most 3 test items with the CLI (`cargo run -p cli -- publish --source m2-test
     --title ... --summary ... --ttl 3600`, OS_WIDGET_SERVER=https://os-widget.longdaobk17.workers.dev,
     OS_WIDGET_PUBLISH_TOKEN read from Keychain service `os-widget-publish-token` without echo). Likewise you may
     run read-only GETs with the client token (service `os-widget-client-token`). No PATCH/DELETE on the
     server. Report the join reply verbatim (no keys) and whether an INSERT signal arrived.
3. Out of scope: other phases, docs/, plan and phase files, spikes/.

Checks
- `cd apps/macos/OSWidgetKit && swift test` passes (paste counts per suite); the 42 existing tests still pass.
- `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <your scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`
  succeeds without compiler warnings in your files.
- `git diff --name-only main...HEAD` lists only files in your write scope plus your report.
- `git grep -n "import WidgetKit" apps/macos` empty. No token, key or personal data in code, tests or logs.
- No plan/phase/milestone IDs in code, comments, test names, commit messages, branch name.
- A flaky test: rerun it alone and report it; do not edit the test to pass.

Rules
- Write scope: the worktree ../os-widget-macos-sync: apps/macos/OSWidgetKit/Sources/OSWidgetKit/Sync/**, apps/macos/OSWidgetKit/Tests/OSWidgetKitTests/{SyncEngine,APIClient,RealtimeSignal}Tests.swift (and Sync*-prefixed test helpers), apps/macos/App/SyncWiring.swift; your report.
- No Cloudflare/Supabase admin, no GitHub, no push. Do not read or write Keychain items except as stated above.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working on anything not blocked.
- Leave the worktree and branch in place for review.
- Report: plans/reports/cook-261123-m2-p03.md in Vietnamese, committed on the branch.

When done, SendMessage m0-supervisor with: branch head SHA, commits, swift test counts per suite, unsigned build
result, files changed, any public API you added, the checks deferred to after 30/11, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
