# Brief: m2-menu-bar-app-p04-review

You are session "m2-menu-bar-app-p04-review". Your only job: review branch `macos-menu-bar-list` (Phase 4 of the
M2 plan: menu bar list, status menu, item cards, launch at login) with `/ak-code-review`, fix small findings on
the branch, merge it `--no-ff` into main locally, and record the phase status. The supervisor is session
"m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Branch `macos-menu-bar-list`, head c989b27, worktree ../os-widget-macos-menubar, based on main 3db956b.
  Commits: 7263a03 (code), c989b27 (cook report plans/reports/cook-261123-m2-p04.md).
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md, phase-04-thanh-menu-danh-sach-va-the.md, skim phase-05
  (the popup will reuse CardView(item:) and URLPolicy, and post Notification.Name.openItemListRequested).
  docs/architecture.md §3 (blocks), §5, §7. The cook report.
- Supervisor already verified: swift test 56 tests in 6 suites pass; the diff touches only App/LaunchAtLogin.swift,
  App/MenuBar/**, OSWidgetKit/Sources/OSWidgetKit/Cards/**, Tests/CardsTests.swift and the report; no edits to
  Package.swift, project.yml, AppDelegate.swift, AppEnvironment.swift; no `syncRequested`.
- Supervisor decisions already applied (keep them): Phase 3 starts a sync itself when ItemStore.queue gains an
  action, so Phase 4 posts no sync notification. Phase 4 owns
  `Notification.Name.openItemListRequested` ("local.oswidget.open-item-list"); MenuBarController observes it and
  does nothing when the list is already open. `isListOpen` is now computed from `popover.isShown` (accepted).
- Cook concern to resolve (supervisor decision): clicking a link inside a card must open only that link (if
  URLPolicy.isOpenable) and mark the item read; it must NOT also trigger the card's own tap action or open the
  item's own url. Fix it on the branch (e.g. handle the link through an OpenURLAction in the environment so the
  card tap gesture does not fire), with a test where testable. If the phase file says otherwise, follow the
  phase file and say so in the report.
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Verify only with `swift test` and
  unsigned builds; no signing, installing, running the app, or App Group container access until 2026-11-30.
  Checks that need the running app are deferred to Phase 6; do not raise them as findings.
- Running in parallel: p03-cook (worktree ../os-widget-macos-sync, OSWidgetKit Sync/ + App/SyncWiring) and
  p05-cook (worktree ../os-widget-macos-popup, App/Popup/**). Do not touch their worktrees or branches. After your
  merge, p05's review integrates CardView(item:), URLPolicy and the openItemListRequested post. Keep those public
  signatures stable; if you change one, list it explicitly in your report and message.

Work
1. Review main..macos-menu-bar-list for correctness against phase-04 (list ordering, unread dot, mark read on
   open, delete, status menu toggles calling only setQuietMode/setPopup, Markdown rendering, URLPolicy rejecting
   non-http(s)/javascript/file schemes and https-only image loading, unknown block fallback, vocab fallback card),
   Swift 6 concurrency / MainActor isolation, SMAppService usage (written, never executed), and test gaps.
2. Fix small findings on the branch in the worktree, each its own commit with a test where testable. A finding
   needing an operator decision: report with a recommendation, do not merge.
3. Re-run Checks, then in the main checkout: `git merge --no-ff macos-menu-bar-list`.
4. On main: phase-04 frontmatter `status: completed`, a short "Ghi chú" (operator decision quoted above; the
   link-click decision; checks deferred to Phase 6 listed by the cook). plan.md Phases table row 4 → "Done
   (chưa chạy app)". Edit only row 4 (another review may edit row 3 later). Commit
   `docs: mark menu bar list phase done` together with your report.
5. Remove the worktree ../os-widget-macos-menubar and delete branch macos-menu-bar-list.
6. Out of scope: phases 3, 5, 6, docs/, spikes/.

Checks
- On main after merge: `cd apps/macos/OSWidgetKit && swift test` passes (paste counts);
  `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`
  succeeds; `cargo test --workspace` passes; `git grep -n "import WidgetKit" apps/macos` empty.
- `git status` clean apart from pre-existing untracked files.
- No plan/phase/milestone IDs in code, comments, test names, commit messages.

Rules
- Write scope: the worktree ../os-widget-macos-menubar, the merge on main, phase-04 file and plan.md row 4, your
  report.
- Never sign, never `-allowProvisioningUpdates`, never launch the app, never run LaunchAtLogin / SMAppService,
  never touch WidgetProbe, the App Group container or the Keychain. No server calls, no Cloudflare, Supabase,
  GitHub, no push.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working on anything not blocked.
- Report: plans/reports/review-261123-m2-p04.md in Vietnamese.

When done, SendMessage m0-supervisor with: findings and handling (commit SHAs), any public API change, merge
SHA, status commit SHA, swift test counts and build result on main, worktree/branch removed; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
