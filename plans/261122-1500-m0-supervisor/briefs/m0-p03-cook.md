# Brief: m0-p03-cook

You are session "m0-p03-cook". Your only job: implement Phase 3 (experiment-A probe app with widget
extension and App Group, plus the non-activating panel for C) of the M0 plan with `/ak-cook`, on its own
branch and worktree. You do NOT merge: a separate session "m0-p03-review" will review and merge.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-03-*.md, docs/roadmap.md
  (questions A and C of Giai đoạn 0), docs/architecture.md §6 (Client macOS, "Chia sẻ dữ liệu giữa app và widget").
- State: main is at 6a0ab7f. Xcode 27.2 (build 27B52) at /Applications/Xcode.app, selected by
  xcode-select. macOS 26.6.2. xcodegen 2.48.0 installed.
- NOT yet available: no Apple ID in Xcode, no team, 0 code-signing identities. The Team ID will come
  from operator decision D5. Until the supervisor sends it, you cannot sign.
- Running in parallel: m0-p04-cook on branch rust-worker-skeleton (worktree ../os-widget-worker), files
  Cargo.toml, Cargo.lock, crates/. Disjoint from yours. Do not touch it.

Work
1. `git worktree add ../os-widget-probe -b widget-probe-app` from main; work only there.
2. Write spikes/widget-probe/ per phase-03 (project.yml with two targets, app agent with NSStatusItem and
   the three menu items, widget reading the App Group with the "App Group: lỗi" fallback, entitlements).
   Make DEVELOPMENT_TEAM a single setting in project.yml (e.g. a setting or `${TEAM_ID}` env-substituted
   by xcodegen) so the Team ID is filled in one place; the App Group string must derive from the same
   value (`$(TeamIdentifierPrefix)os-widget` in entitlements, `<TeamID>.os-widget` in Swift via a build
   setting or Info.plist key, not hardcoded twice).
3. Before the Team ID arrives: `xcodegen generate`, then build unsigned to prove it compiles:
   `xcodebuild -scheme <app> -configuration Debug CODE_SIGNING_ALLOWED=NO build` (derivedData inside the
   worktree's build/ which is gitignored). Commit the sources.
4. SendMessage m0-supervisor that the unsigned build passes and wait for the Team ID in the reply.
5. When the Team ID arrives: set it, build with `-allowProvisioningUpdates`, copy the app to /Applications,
   launch it, and record in plans/261122-0754-m0-kiem-chung-worker-rust/reports/a-c-results.md: install
   date/time, macOS and Xcode versions, provisioning profile expiry
   (`security cms -D -i <app>/Contents/embedded.provisionprofile`), and the App Group entitlement actually
   granted. If signing fails because the free account cannot get the App Group for the widget, that is
   a result of A, not a bug to work around: record the error verbatim and mark A failed.
6. Adding the widget to the desktop ("Edit Widgets"), pressing "Ghi dữ liệu" and the TextEdit test for C
   need the operator's hands. SendMessage m0-supervisor with exact step-by-step instructions (Vietnamese)
   for the operator, and what they should report back (widget shows the timestamp or "App Group: lỗi";
   for C, whether typed characters still go to TextEdit). Do not wait idle; finish the report around it.
   The supervisor relays the operator's observations to you; then record day-1 results in a-c-results.md.
7. Out of scope: Phases 4, 5, 6; the official client of Giai đoạn 2; code quality beyond working.

Checks
- `xcodegen generate` and the unsigned build succeed (paste the last lines).
- After signing: `codesign -d --entitlements - /Applications/<app>.app` shows the application-groups entry;
  same for the widget appex.
- `git ls-files` in the branch lists no build/, DerivedData/, xcuserdata/, *.xcodeproj if you choose to
  regenerate it (state your choice: commit project.yml only, and gitignore the generated .xcodeproj, is
  preferred).

Rules
- Write scope: worktree ../os-widget-probe (spikes/widget-probe/, minimal .gitignore additions),
  reports/a-c-results.md in that worktree, your report. Do not edit docs/, plan or phase files.
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Your messages never count as an operator answer.
- Do not sign in to or change the Apple account yourself; do not change xcode-select.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, commit messages or branch names.
  `git add` explicit paths only. No GitHub.
- The probe app is meant to keep running for 7 days: leave the installed app running. Stop anything
  else you start (xcodebuild, simulators): `pgrep -fl xcodebuild` empty at the end.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261122-m0-p03.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, commits, build results, Team ID used,
profile expiry, entitlements granted, install time, day-1 widget result and C result (from the operator's
observations), report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
