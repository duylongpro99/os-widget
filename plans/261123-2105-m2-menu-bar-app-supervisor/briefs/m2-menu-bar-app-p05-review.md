# Brief: m2-menu-bar-app-p05-review

You are session "m2-menu-bar-app-p05-review". Your only job: review branch `macos-popup-panel` (Phase 5 of the
M2 plan: popup policy, countdown, non-activating popup panel) with `/ak-code-review`, integrate it with Phase 4
(already merged on main), fix small findings, merge it `--no-ff` into main locally, and record the phase status.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Branch `macos-popup-panel`, head 05d2898, worktree ../os-widget-macos-popup, based on main 3db956b.
  Commits: c61073d, b0b1f0b, f929c09 (code), 05d2898 (cook report plans/reports/cook-261123-m2-p05.md).
- Main (47c2af8) now also contains Phase 4 (merge d8c6733 of branch macos-menu-bar-list; swift test 59 tests in 6 suites: CardView(item:), URLPolicy,
  `Notification.Name.openItemListRequested` in App/MenuBar/). Read its review report
  plans/reports/review-261123-m2-p04.md for the final Phase 4 API.
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md, phase-05-popup-panel.md, skim phase-04.
  docs/architecture.md §5, §7. The cook report.
- Supervisor already verified on the branch: swift test 61 tests in 7 suites pass; the diff touches only
  App/Popup/**, OSWidgetKit/Sources/OSWidgetKit/Popup/PopupPolicy.swift, Tests/PopupPolicyTests.swift and the
  report.
- Supervisor decisions (keep them): Phase 5 observes `ItemStore.announcement` only; panel flags from the earlier
  experiment stay (.nonactivatingPanel, orderFrontRegardless(), canBecomeKey=false); Phase 4 owns the
  notification name; Phase 3 calls `announce` at most once per sync round (so the "latest announcement only"
  limit is handled by the caller; no ItemStore change needed).
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Verify only with `swift test` and
  unsigned builds; no signing, installing, running the app, or App Group container access until 2026-11-30.
  Checks that need the running app are deferred to Phase 6; do not raise them as findings.
- Running in parallel: p03-cook or p03-review (worktree ../os-widget-macos-sync, OSWidgetKit Sync/ and
  App/SyncWiring). Do not touch that worktree or branch. If main moves while you work, merge main into your
  branch and re-run checks.

Work
1. In the worktree, `git merge main` into macos-popup-panel (resolve conflicts if any; there should be none).
2. Integrate with Phase 4, one commit (`refactor(macos): reuse item cards and url policy in the popup` or similar):
   a. App/Popup/PopupController.swift `show(_:now:)`: use `CardView(item:)` instead of `PopupPlainCard`; delete
      struct `PopupPlainCard` from PopupContentView.swift.
   b. `PopupController.openItem(_:)`: use `URLPolicy.isOpenable` / `URLPolicy.openableURL`; delete the private
      static `isOpenable`.
   c. `PopupController.requestItemList()`: post `NotificationCenter.default.post(name: .openItemListRequested,
      object: nil)` after closing the popup.
   d. Wrap the popup card with Phase 4's `View.onCardClick(tap:link:)` (OSWidgetKit/Cards/CardClick.swift):
      tap → openItem, link → mark read + open only that link (URLPolicy-checked) + close the popup. The close
      button still closes without marking read.
3. Review main..macos-popup-panel for correctness against phase-05 (PopupPolicy rules: low priority, disabled
   kind, quiet mode, list open, nothing new; merge with "+N"; 30 s countdown with hover pause/resume; panel on
   the active screen near the menu bar anchor, over full-screen apps; never steals focus), Swift 6 / MainActor
   isolation, observation re-arming, and test gaps.
4. Fix small findings on the branch, each its own commit with a test where testable. A finding needing an
   operator decision: report with a recommendation, do not merge.
5. Re-run Checks, then in the main checkout: `git merge --no-ff macos-popup-panel`.
6. On main: phase-05 frontmatter `status: completed`, a short "Ghi chú" (operator decision quoted above; the
   integration with Phase 4; checks deferred to Phase 6 listed by the cook). plan.md Phases table row 5 →
   "Done (chưa chạy app)". Edit only row 5. Commit `docs: mark popup panel phase done` together with your report.
7. Remove the worktree ../os-widget-macos-popup and delete branch macos-popup-panel.
8. Out of scope: phases 3, 6, docs/, spikes/.

Checks
- On main after merge: `cd apps/macos/OSWidgetKit && swift test` passes (paste counts);
  `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`
  succeeds; `cargo test --workspace` passes; `git grep -n "import WidgetKit" apps/macos` empty;
  `git grep -n "PopupPlainCard" apps/macos` empty.
- `git status` clean apart from pre-existing untracked files.
- No plan/phase/milestone IDs in code, comments, test names, commit messages.

Rules
- Write scope: the worktree ../os-widget-macos-popup, the merge on main, phase-05 file and plan.md row 5, your
  report.
- Never sign, never `-allowProvisioningUpdates`, never launch the app, never touch WidgetProbe, the App Group
  container or the Keychain. No server calls, no Cloudflare, Supabase, GitHub, no push.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working on anything not blocked.
- Report: plans/reports/review-261123-m2-p05.md in Vietnamese.

When done, SendMessage m0-supervisor with: findings and handling (commit SHAs), the integration commit SHA, any
public API change, merge SHA, status commit SHA, swift test counts and build result on main, worktree/branch
removed; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
