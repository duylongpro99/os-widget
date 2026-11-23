# Brief: m2-menu-bar-app-p02-review

You are session "m2-menu-bar-app-p02-review". Your only job: review branch `macos-local-store` (Phase 2 of the
M2 plan: models, local store, action queue) with `/ak-code-review`, fix small findings on the branch, merge it
`--no-ff` into main locally, and record the phase status. The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Branch `macos-local-store`, head 7c56a6b, worktree ../os-widget-macos-store, based on main 037309e.
  Commits: 431198d (code), 7c56a6b (cook report plans/reports/cook-261123-m2-p02.md).
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md, phase-02-kho-cuc-bo-va-hang-doi.md, and phases
  03, 04, 05 (they will consume this public API right after you merge: apply/replaceAll/announce/
  announcement, markRead/delete, complete(_:outcome:), PendingAction.outcome(for:), popupSettings,
  setPopup(kind:enabled:), setQuietMode). docs/architecture.md §3, §4.1, §4.3, §5. The cook report.
- Supervisor already verified: swift test 41 tests in 5 suites pass; diff touches only apps/macos/OSWidgetKit/**
  and the report; fixtures contain no tokens or personal data.
- Cook's deviations to judge (accept if sound): outcome 408/429 → retry, other 4xx → drop like 400;
  `live()` falls back to an in-memory store and logs when the container is unavailable; Package.swift adds
  test resources `.copy("Fixtures")`.
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Verify only with `swift test` and
  unsigned builds; no signing, installing, running the app, or App Group container access until 2026-11-30.
- Next: after your merge, phases 3, 4 and 5 start in parallel on this API. If you would change a public name
  or signature, keep the change small and list it explicitly in your report and message.

Work
1. Review main..macos-local-store for correctness against architecture §5 (idempotent apply, cursor only
   increases, delete wins over read, queued actions re-applied after server state, expiry pruning,
   replaceAll semantics), atomic write and corrupt-file recovery, Swift 6 concurrency, date decoding with
   6-digit fractional seconds, tolerant decoding (unknown kind/block/event type), and test gaps against the
   phase's test table.
2. Fix small findings on the branch in the worktree, each its own commit with a test where testable. A
   finding needing an operator decision: report with a recommendation, do not merge.
3. Re-run Checks, then in the main checkout: `git merge --no-ff macos-local-store`.
4. On main: phase-02 frontmatter `status: completed`, a short "Ghi chú" (operator decision quoted above;
   fixtures source; accepted deviations). plan.md Phases table row 2 → "Done". Commit
   `docs: mark local store phase done` together with your report.
5. Remove the worktree ../os-widget-macos-store and delete branch macos-local-store.
6. Out of scope: phases 3–6, App/, docs/, spikes/.

Checks
- On main after merge: `cd apps/macos/OSWidgetKit && swift test` passes (paste counts);
  `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`
  succeeds; `cargo test --workspace` passes; `git grep -n "import WidgetKit" apps/macos` empty.
- `git status` clean apart from pre-existing untracked files.
- No plan/phase/milestone IDs in code, comments, test names, commit messages.

Rules
- Write scope: the worktree, the merge on main, phase-02 file and plan.md row 2, your report.
- Never sign, never `-allowProvisioningUpdates`, never launch the app, never touch WidgetProbe, the App Group
  container or the Keychain. No server calls, no Cloudflare, Supabase, GitHub, no push.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working on anything not blocked.
- Report: plans/reports/review-261123-m2-p02.md in Vietnamese.

When done, SendMessage m0-supervisor with: findings and handling (commit SHAs), any public API change, merge
SHA, status commit SHA, swift test counts and build result on main, worktree/branch removed; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
