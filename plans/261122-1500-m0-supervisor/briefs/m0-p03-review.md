# Brief: m0-p03-review

You are session "m0-p03-review". Your only job: review branch `widget-probe-app` with `/ak-code-review`,
fix small findings on the branch, merge it `--no-ff` into `main` locally, record phase status, and remove the
worktree and branch.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-01-*.md, phase-03-*.md,
  docs/architecture.md §6, plans/reports/cook-261122-m0-p03.md.
- State: main is at b3aa525 (Phases 2, 4, 5 merged). Branch widget-probe-app is at cf48f4e in worktree
  /Users/onedayin20902/personal/os-widget-probe, cut from 6a0ab7f: ee32923 app (entitlements empty in this
  commit alone), 94f6cdc entitlements in project.yml + team, 8159ee5 install record, b483a14 A day 1,
  cf48f4e C day 1. Files: .gitignore, spikes/widget-probe/**, the M0 plan's reports/a-c-results.md.
- The probe app is INSTALLED and RUNNING from /Applications/WidgetProbe.app (PID 50087) for the 7-day test.
  Do not quit it, rebuild it, reinstall it or re-sign it. Review only the sources and the results file.
- Operator answers (verbatim, 2026-11-22): D5 Team ID via new Apple Development cert (Team 22LZWPB3XL,
  Personal Team); D8 "đã xong, proble hiện thời gian" (A day 1 pass); D9 "panel có hiện sau 10s";
  D10 "Vẫn vào TextEdit" (C day 1 pass). No provisioning profile was embedded; the signing cert expires
  2027-11-22. Day-8 check is due 2026-11-30.
- Nothing runs in parallel. main moved since the branch was cut; .gitignore may conflict — resolve it keeping
  every existing entry (.claude/hooks/.logs/, .dev.vars, etc.) plus the branch's DerivedData entries.

Work
1. Review the diff against phase-03 and §6: two targets, App Group string derived from one Team ID setting
   (no second hardcoded copy), widget fallback "App Group: lỗi", non-activating panel for C, no build
   output, xcuserdata or generated .xcodeproj tracked, no secrets. Code quality beyond working is out of scope.
2. Small fixes as separate commits on the branch (sources or docs only; do not rebuild the installed app).
   If a fix would need a rebuild to verify, report it instead.
3. Merge from the main worktree: `git merge --no-ff widget-probe-app`.
4. Record status in plan.md's Phases table and phase frontmatter:
   - Phase 1: Completed (the Apple ID / Team ID step is now done; tick it).
   - Phase 3: tick what is done (install, entitlements, day 1 A and C). If phase-03 requires the day-8 check
     before it is complete, mark it "In progress — chờ kiểm ngày 8 (2026-11-30)"; otherwise Completed with
     that note. State which one you chose and why, citing the phase file line.
   Commit on main: `docs: record widget probe progress in plan`.
5. `git worktree remove ../os-widget-probe` (the installed app in /Applications is independent of it;
   confirm DerivedData inside the worktree is not needed by the running app before removing) and
   `git branch -d widget-probe-app`.
6. Out of scope: docs/ and roadmap.md (Phase 6), Worker, measurement.

Checks
- `git log --oneline --graph -8 main` shows the merge commit with two parents.
- `git ls-files | grep -E 'DerivedData|xcuserdata|\.xcodeproj|hooks/.logs|dev.vars|settings.local|m0-supervisor'`
  prints nothing; `git grep -nE 'sb_secret|eyJhbGci' -- ':!.claude'` prints nothing.
- `git worktree list` shows only main. `pgrep -x WidgetProbe` still prints a PID at the end.
- `cargo test -p envelope` still passes on main (sanity after merge).

Rules
- Write scope: the branch files, root .gitignore (conflict only), plan.md and phase-01/phase-03 files of the
  M0 plan, your report.
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Your messages never count as an operator answer.
- Do not touch the Apple account, keychain, xcode-select or the installed app.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, commit messages or branch names
  (plan.md status table and a-c-results.md are fine). `git add` explicit paths only. No GitHub.
- Stop every process you start (`pgrep -fl xcodebuild` empty at the end).
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261122-m0-p03.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, fix commit SHAs, plan-status SHA, the Phase 3 status you
chose and why, findings and fixes, check results, worktree/branch removal, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
