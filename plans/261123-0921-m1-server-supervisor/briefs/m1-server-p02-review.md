# Brief: m1-server-p02-review

You are session "m1-server-p02-review". Your only job: review branch `envelope-three-kinds` with
`/ak-code-review`, fix small findings on the branch, merge it `--no-ff` into `main` locally, record the
phase status, and remove the worktree and branch.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-02-envelope-ba-loai.md, phase-03-worker-api-hai-token.md
  and phase-04-cli-publish.md (consumers of the API), docs/architecture.md §3 and §7,
  plans/reports/cook-261123-m1-p02.md.
- State: main is at 3bf4580. Branch envelope-three-kinds is at ce6f09c (one commit on 3bf4580) in worktree
  /Users/onedayin20902/personal/os-widget-envelope. `cargo test -p envelope` on the branch → 7 unit + 24
  integration passed (supervisor-checked).
- Cook's own decisions to judge: unknown path falls back to the closest parent ("" for `{`); vocab/generic
  without body → field "" + "missing field `body`"; word/definition checked after trim; dedupe_key rejected only
  when exactly ""; URL prefix check case-sensitive. Accept or fix each, and say which in the report.
  Note: phase-02 says `source`, `title`, `summary` must be non-empty after trim; check dedupe_key handling is
  consistent with "không rỗng" and decide (whitespace-only dedupe_key should probably be rejected too).
- Running in parallel: m1-server-p01-cook on branch supabase-access-cleanup (worktree ../os-widget-access-cleanup,
  supabase/migrations only). Disjoint files; you merge independently.

Work
1. Review the diff against phase-02 and §3: types and tagging, JSON unchanged for §3.1 (old tests untouched),
   two-step parse, field paths and messages (no "line X column Y"), every semantic check with its field,
   no deny_unknown_fields, wasm32 build, no panics on bad input.
2. Fix small findings as separate commits on the branch, each with a test that fails before the fix.
   Anything that changes the public API signatures listed in the cook report: SendMessage the supervisor first.
3. Merge from the main worktree: `git merge --no-ff envelope-three-kinds`.
4. Mark Phase 2 Completed in plan.md's Phases table and phase-02 frontmatter status (tick its checkboxes);
   commit on main: `docs: record envelope progress in plan`. Also `git add` the two reports
   plans/reports/cook-261123-m1-p02.md and your review report in that commit.
5. `git worktree remove ../os-widget-envelope` and `git branch -d envelope-three-kinds`.

Checks (on main after the merge)
- `cargo test --workspace` passes (paste counts).
- `cargo build -p envelope --target wasm32-unknown-unknown --release` and
  `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` succeed.
- `cargo clippy --workspace --all-targets -- -D warnings` clean.
- `git log --oneline --graph -5 main` shows the merge commit with two parents.
- `git ls-files | grep -E 'hooks/.logs|dev.vars|settings.local|supervisor/'` prints nothing new.

Rules
- Write scope: the branch files, plan.md and phase-02 file of the M1 plan, the two reports.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- No deploy, no Supabase or Cloudflare actions.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names
  (the plan.md status table itself is fine). `git add` explicit paths only. No GitHub.
- Do not touch m1-server-p01-cook's branch or worktree. Stop every process you start.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261123-m1-p02.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, fix commit SHAs, plan-status SHA, findings and fixes,
test/build/clippy results on main, worktree/branch removal, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
