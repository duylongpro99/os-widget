# Brief: m2-menu-bar-app-p03-review

You are session "m2-menu-bar-app-p03-review". Your only job: review branch `macos-sync-engine` (Phase 3 of the
M2 plan: API client, sync engine, hand-written Phoenix Realtime signal, triggers, SyncWiring) with
`/ak-code-review`, bring it up to date with main, fix small findings, merge it `--no-ff` into main locally, and
record the phase status. The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Branch `macos-sync-engine`, head 877e0f9, worktree ../os-widget-macos-sync, based on main 3db956b.
  Commits: 19e2fb7 (code), 877e0f9 (cook report plans/reports/cook-261123-m2-p03.md).
- Main is now b25df53: phases 1, 2, 4, 5 merged (Phase 4 merge d8c6733, Phase 5 merge 037e9eb); swift test
  78 tests in 8 suites on main. Phase 5's popup observes `ItemStore.announcement`; Phase 4/5 call only
  ItemStore.markRead/delete.
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md, phase-03-sync-engine.md; docs/architecture.md §4
  (API, events, Realtime), §5 (sync algorithm), §7. The cook report. Skim plans/reports/review-261123-m2-p05.md.
- Supervisor already verified on the branch: swift test 81 tests in 8 suites (1 live test skipped by default);
  diff touches only OSWidgetKit Sync/**, its tests and SyncTestSupport, App/SyncWiring.swift and the report;
  the "Bearer" strings in tests are fake values.
- Supervisor decisions (keep them): Phase 3 owns the sync-after-action trigger (QueueWatcher observes
  ItemStore.queue, triggers only on new action ids, never on removals or retries); `announce` is called at most
  once per round with all new items; queue send and event fetch run sequentially in one round; rounds never
  overlap. Live Realtime check is deferred to Phase 6 (the publishable key was not available); do not retry the
  supabase CLI.
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Verify only with `swift test` and
  unsigned builds; no signing, installing, running the app, or App Group container access until 2026-11-30.
  Checks that need the running app or live server are deferred to Phase 6; do not raise them as findings.
- Running in parallel: nothing else in this repo.

Work
1. In the worktree, `git merge main` into macos-sync-engine; resolve conflicts if any (App/SyncWiring.swift is the
   only shared-looking file; main did not change it). Re-run swift test.
2. Review main..macos-sync-engine for correctness against phase-03 and architecture §5: cursor only increases and
   is saved after apply; 410/gap → full reconcile via replaceAll; pagination; queue outcomes per
   PendingAction.outcome(for:) (401/403 stop and surface, retry with backoff); no overlapping rounds; Realtime
   only as a signal (Phoenix join/heartbeat/reply parsing, reconnect backoff with jitter, stop on sleep, resume on
   wake/network); token never logged (check SyncLog and every log call); Swift 6 concurrency (actors,
   Sendable, MainActor hops to ItemStore); cancellation and task cleanup on stop; and test gaps.
3. Judge the known limit "changing only the token does not trigger an immediate sync": if a fix is small
   (e.g. trigger a round when credentials change in SyncWiring), do it with a test; otherwise note it.
4. Fix small findings on the branch, each its own commit with a test where testable. A finding needing an
   operator decision: report with a recommendation, do not merge.
5. Re-run Checks, then in the main checkout: `git merge --no-ff macos-sync-engine`.
6. On main: phase-03 frontmatter `status: completed`, a short "Ghi chú" (operator decision quoted above; live
   Realtime check deferred to Phase 6 and why; other deferred checks from the cook report). plan.md Phases table
   row 3 → "Done (chưa chạy app)". Edit only row 3. Commit `docs: mark sync engine phase done` together with
   your report.
7. Remove the worktree ../os-widget-macos-sync and delete branch macos-sync-engine.
8. Out of scope: phases 4, 5, 6 (except merge conflicts), docs/, spikes/.

Checks
- On main after merge: `cd apps/macos/OSWidgetKit && swift test` passes (paste counts; expect about 78 + 39
  new); `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`
  succeeds; `cargo test --workspace` passes; `git grep -n "import WidgetKit" apps/macos` empty.
- `git status` clean apart from pre-existing untracked files.
- No plan/phase/milestone IDs in code, comments, test names, commit messages.

Rules
- Write scope: the worktree ../os-widget-macos-sync, the merge on main, phase-03 file and plan.md row 3, your
  report.
- Never sign, never `-allowProvisioningUpdates`, never launch the app, never touch WidgetProbe, the App Group
  container or the Keychain. No server calls (do not set OSWIDGET_LIVE_REALTIME), no Cloudflare, Supabase,
  GitHub, no push.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working on anything not blocked.
- Report: plans/reports/review-261123-m2-p03.md in Vietnamese.

When done, SendMessage m0-supervisor with: findings and handling (commit SHAs), any public API change, merge
SHA, status commit SHA, swift test counts and build result on main, worktree/branch removed; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
