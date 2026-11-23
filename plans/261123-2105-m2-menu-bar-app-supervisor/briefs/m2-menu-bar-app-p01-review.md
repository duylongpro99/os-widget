# Brief: m2-menu-bar-app-p01-review

You are session "m2-menu-bar-app-p01-review". Your only job: review branch `macos-app-project` (Phase 1 of the
M2 plan: Xcode project, OSWidgetKit package, configuration) with `/ak-code-review`, fix small findings on the
branch, merge it `--no-ff` into main locally, and record the phase status. The supervisor is session
"m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Branch `macos-app-project`, head 57cc98c, worktree ../os-widget-macos-app, based on main 29dd016.
  Commits: e8cd5ad (code), 57cc98c (cook report plans/reports/cook-261123-m2-p01.md).
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md, phase-01-xcode-project-va-cau-hinh.md, skim
  phase-02..05 (they consume the hook signatures: AppEnvironment, ItemStore shell, SyncWiring.start(env:),
  MenuBarController(env:) with anchorRect()/isListOpen, PopupController(env:anchor:isListOpen:), StoreLocation
  with injectable base directory). docs/architecture.md §6, §7. The cook report.
- Supervisor already verified: swift test 7 tests in 2 suites pass; Team ID only in project.yml:11;
  entitlements sandbox + network.client + application-groups $(TeamIdentifierPrefix)os-widget; root .gitignore
  adds only apps/macos/*.xcodeproj/. An extra apps/macos/OSWidgetKit/.gitignore (.build/, .swiftpm/) is accepted.
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Phases 1–5 are verified only
  with `swift test` and unsigned builds. Signing, installing, running the app and the App Group container wait
  for experiment A's day-8 check (2026-11-30). Do not ask for those checks as findings; they are deferred.
- Nothing runs in parallel in this repo.

Work
1. Review the diff main..macos-app-project for correctness (hook signatures match phases 2–5, Swift 6 strict
   concurrency, Keychain query attributes, single-instance check, settings window activation, StoreLocation
   error handling), security (token never logged or shown in plain text, never in UserDefaults), and test gaps.
2. Fix small findings on the branch in the worktree, each its own commit, with a test where testable. A finding
   that needs an operator decision or changes a hook signature: report it with a recommendation, do not merge.
3. Re-run Checks, then in the main checkout: `git merge --no-ff macos-app-project`.
4. On main, mark Phase 1 done: phase-01 frontmatter `status: done-pending-signing` is NOT a valid value — use
   `status: completed` and, under the phase file, a short "Ghi chú" listing: A branch not yet chosen (coded for
   "A đạt"), operator decision quoted above, and the deferred verification items (signed build, codesign
   entitlements, menu bar icon without Dock, Keychain round-trip, StoreLocation.appGroup with the real
   container) "hoãn tới sau 30/11, làm ở Phase 6". In plan.md Phases table set row 1 to "Done (chưa ký)".
   Commit `docs: mark menu bar app project setup done`.
5. Remove the worktree ../os-widget-macos-app and delete branch macos-app-project.
6. Out of scope: phases 2–6, docs/, spikes/.

Checks
- `cd apps/macos/OSWidgetKit && swift test` passes on main after merge (paste counts).
- `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`
  succeeds on main after merge.
- `cargo test --workspace` passes. `git status` clean apart from the pre-existing untracked files
  (.agentkit/, .claude/pr-review-loop/, __pycache__, plans/*-supervisor state files).
- No plan/phase/milestone IDs in code, comments, test names, commit messages.

Rules
- Write scope: the worktree, the merge on main, phase-01 file and the Phases table row 1 in plan.md, your report.
- Never sign with the Apple account, never `-allowProvisioningUpdates`, never launch the app, never touch
  /Applications/WidgetProbe.app, its widget, ~/Library/Group Containers/22LZWPB3XL.os-widget or the Keychain.
  No Cloudflare, Supabase, GitHub, no push.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names or commit messages.
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working on anything not blocked.
- Write your report to plans/reports/review-261123-m2-p01.md in Vietnamese (commit it with the status commit).

When done, SendMessage m0-supervisor with: findings and how each was handled (commit SHAs), merge SHA, status
commit SHA, swift test counts and build result on main, worktree/branch removed; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
