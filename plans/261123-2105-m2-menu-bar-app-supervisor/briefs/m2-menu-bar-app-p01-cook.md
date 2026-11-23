# Brief: m2-menu-bar-app-p01-cook

You are session "m2-menu-bar-app-p01-cook". Your only job: implement Phase 1 (Xcode project, shared package
and configuration) of the M2 plan with `/ak-cook`, on its own branch and worktree, WITHOUT signing, installing
or running the app. You do NOT merge: a separate session "m2-menu-bar-app-p01-review" will review and merge.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md, phase-01-xcode-project-va-cau-hinh.md, and skim
  phase-02..05 (they consume the hook signatures you fix now: ItemStore shell, SyncWiring.start(env:),
  MenuBarController(env:) with anchorRect()/isListOpen, PopupController(env:anchor:isListOpen:)).
  docs/architecture.md §6 and §7. Read-only templates: spikes/widget-probe/project.yml,
  spikes/widget-probe/App/ (ProbeApp.swift, entitlements, Info.plist).
- State: main is at 29dd016. `apps/` does not exist yet. Xcode 27.2, xcodegen 2.48.0 installed.
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Meaning: code phases 1–5 now,
  verify only with `swift test` and unsigned builds. Signing with the Apple account, installing, running the
  app and touching the App Group container wait for experiment A's day-8 check (2026-11-30).
  The plan's precondition 1 (wait for A) is relaxed by this decision for coding only.
- A branch: unknown until 2026-11-30. Code the "A đạt" branch (App Group entitlement, StoreLocation uses the
  group container via `AppGroupID`), keeping Team ID in exactly one place in project.yml so a later change
  is one line. StoreLocation must take an injectable base directory so tests never touch the real container.
- Running in parallel: nothing in this repo.

Work
1. `git worktree add ../os-widget-macos-app -b macos-app-project` from main; work only there.
2. Implement phase-01 Requirements and Files exactly (project.yml with DEVELOPMENT_TEAM 22LZWPB3XL as the
   single Team ID, APP_GROUP_ID derived from it, entitlements, Info.plist AppGroupID, AppDelegate,
   AppEnvironment, the three hook skeletons with the fixed signatures, SettingsWindow, OSWidgetKit package
   with Config/ files, ItemStore shell, ConfigTests, README.md, .gitignore line for apps/macos/*.xcodeproj/).
3. Instead of the phase's signed build, verify with an unsigned build (see Checks). Do NOT run
   `-allowProvisioningUpdates`, do not sign with Team 22LZWPB3XL, do not launch the built app.
4. In your report list the phase-01 Verification items you could not run because of the decision above
   (signed build, codesign entitlements, menu bar icon, Keychain round-trip) as "hoãn tới sau 30/11".
5. Out of scope: phases 2–6, docs/, plan and phase files, spikes/.

Checks
- `cd apps/macos/OSWidgetKit && swift test` passes (paste counts).
- `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <scratch or build dir outside repo> CODE_SIGNING_ALLOWED=NO
  CODE_SIGN_IDENTITY="" build` succeeds (paste the last lines).
- The entitlements file contains app-sandbox, network.client and application-groups
  `$(TeamIdentifierPrefix)os-widget`; `grep -rn 22LZWPB3XL apps/macos` shows only project.yml.
- `git status` in the worktree shows no .xcodeproj; `cargo test --workspace` still passes.
- No IDs: `git log main..HEAD` messages and new files contain no plan/phase/milestone IDs.
- A flaky test: rerun it alone and report it; do not edit the test to pass.

Rules
- Write scope: the worktree ../os-widget-macos-app (apps/macos/**, root .gitignore line), your report.
- Never touch /Applications/WidgetProbe.app, its widget, ~/Library/Group Containers/22LZWPB3XL.os-widget, or
  the login Keychain (no `security add-generic-password` etc.). No Cloudflare, Supabase, GitHub, Apple account.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names.
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261123-m2-p01.md in Vietnamese (inside the worktree, committed on
  the branch).

When done, SendMessage m0-supervisor with: branch head SHA, commits, swift test counts, unsigned build result,
the exact hook signatures, the checks deferred to after 30/11, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
