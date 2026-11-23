# Brief: m1-server-p04-review

You are session "m1-server-p04-review". Your only job: review branch `cli-publish` with `/ak-code-review`,
fix small findings on the branch, merge it `--no-ff` into `main` locally, record the phase status, and remove
the worktree and branch.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-04-cli-publish.md, phase-03-worker-api-hai-token.md
  (server contract), phase-05-deploy-va-nghiem-thu.md (acceptance script runs `cargo run -q -p cli -- publish ...`),
  docs/architecture.md §3, §4.1, §4.2, plans/reports/cook-261123-m1-p04.md.
- State: main is at 280c55e. Branch cli-publish is at 61c8855 (one commit on 280c55e) in worktree
  /Users/onedayin20902/personal/os-widget-cli. `cargo test -p cli` → 23 passed (supervisor-checked).
  ureq 3.5.2 with http_status_as_error(false), 30 s global timeout; clap 4.6.9.
- Points to judge: notification without body is sent as `"body": null` (check the server-side parse and the
  M0 storage accept it, and that §3.1 JSON format allows it); token only from env; exit codes match the table;
  stderr messages never include the token.
- Running in parallel: m1-server-p03-cook on branch worker-api-two-tokens (crates/worker/**, maybe Cargo.lock);
  m1-server-p01-cook on supabase-access-cleanup. If you merge before the Worker branch, its reviewer resolves
  Cargo.toml/Cargo.lock conflicts; if main already has it when you merge, you resolve them.

Work
1. Review the diff against phase-04: crate layout, `cargo run -p cli` works, no `worker` in `cargo tree -p cli`,
   flag conflicts, `--link`, `--dry-run`, normalized envelope goes through `envelope::parse`, HTTP mapping, exit codes.
2. Fix small findings as separate commits on the branch, each with a test that fails before the fix.
3. Merge from the main worktree: `git merge --no-ff cli-publish`.
4. Mark Phase 4 Completed in plan.md's Phases table and phase-04 frontmatter status (tick its checkboxes; the
   "real call to the Worker" item stays for Phase 5 — say so in a note). Commit on main:
   `docs: record cli progress in plan`, and `git add` plans/reports/cook-261123-m1-p04.md and your review report
   in that commit.
5. `git worktree remove ../os-widget-cli` and `git branch -d cli-publish`.

Checks (on main after the merge)
- `cargo test --workspace` passes (paste counts).
- `cargo clippy --workspace --all-targets -- -D warnings` clean; `cargo fmt --check` clean.
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` succeeds.
- `cargo run -q -p cli -- publish --dry-run --file <broken vocab>` exits 2 and prints `body.meanings[0]`.
- `git log --oneline --graph -5 main` shows the merge commit with two parents.

Rules
- Write scope: the branch files, plan.md and phase-04 file of the M1 plan, the two reports.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- No calls to the deployed Worker, no tokens, no deploy, no Supabase or Cloudflare actions.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names
  (the plan.md status table itself is fine). `git add` explicit paths only. No GitHub.
- Do not touch other sessions' branches or worktrees. Stop every process you start (any local listener).
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261123-m1-p04.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, fix commit SHAs, plan-status SHA, findings and fixes,
test/build/clippy results on main, worktree/branch removal, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
