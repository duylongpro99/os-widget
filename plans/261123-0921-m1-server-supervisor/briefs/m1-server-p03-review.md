# Brief: m1-server-p03-review

You are session "m1-server-p03-review". Your only job: review branch `worker-api-two-tokens` with
`/ak-code-review`, fix small findings on the branch, merge it `--no-ff` into `main` locally, record the phase
status, and remove the worktree and branch. You do NOT deploy (Phase 5 does).
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-03-worker-api-hai-token.md,
  phase-05-deploy-va-nghiem-thu.md (acceptance criteria your code must pass), docs/architecture.md §3, §4.1–§4.3,
  §5, §7, plans/reports/cook-261123-m1-p03.md, plans/reports/review-261123-m1-p02.md (envelope notes).
- State: main is at 7523776 (envelope merged ebe562f, CLI merged 45ff5e5). `cargo test --workspace` on main →
  cli 23, envelope 7 + 26, worker 0. Branch worker-api-two-tokens is at 7e961f3 (one commit on 280c55e, only
  crates/worker/src/*) in worktree /Users/onedayin20902/personal/os-widget-worker-api; `cargo test -p
  os-widget-worker` → 35 passed (supervisor-checked). The cook ran a full wrangler dev round with correct codes.
- Operator decisions: default ttl 7 days (plan validation, 2026-11-23). No deploy from this session.
- Cook's choices to judge: error code "invalid since" (M0 had "since must be an integer"; check
  scripts/measure-worker.sh and phase-05 do not depend on the old text); JSON 405 for wrong method; hand-written
  router instead of worker::Router so every 404/405 is JSON; identical PUBLISH_TOKEN and CLIENT_TOKEN → every
  request 401. Accept or fix each and say which.
- Also check: body is stored as the re-serialized envelope content (not raw request JSON); `"body": null` from
  the CLI is accepted; dedupe path returns 200 for a soft-deleted existing item; GET /items reads seq before items;
  expires_at comparison is URL-encoded; UUID check before any PostgREST query; constant-time compare for both tokens.
- Running in parallel: m1-server-p01-cook on supabase-access-cleanup (supabase/migrations only). You merge second
  relative to the CLI: resolve any Cargo.toml/Cargo.lock conflict (the branch did not change them, so expect none).

Work
1. Review the diff against phase-03 and §4.
2. Fix small findings as separate commits on the branch, each with a test that fails before the fix. If a fix
   needs a live check, you may run `npx wrangler@4.166.0 dev` the same way the cook did (service role key piped into
   crates/worker/.dev.vars, throwaway tokens, never printed; delete .dev.vars and soft-delete test items afterwards).
3. Merge from the main worktree: `git merge --no-ff worker-api-two-tokens`.
4. Mark Phase 3 Completed in plan.md's Phases table and phase-03 frontmatter status (tick its checkboxes);
   commit on main `docs: record worker api progress in plan`, with plans/reports/cook-261123-m1-p03.md and your
   review report added in that commit.
5. `git worktree remove ../os-widget-worker-api` and `git branch -d worker-api-two-tokens`.

Checks (on main after the merge)
- `cargo test --workspace` passes (paste counts; worker ≥ 35, cli 23, envelope 7 + 26).
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` succeeds.
- `cargo clippy --workspace --all-targets -- -D warnings` and `cargo fmt --check` clean.
- `git grep -n SPIKE_TOKEN -- crates` empty; `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'` empty.
- `git log --oneline --graph -5 main` shows the merge commit with two parents.

Rules
- Write scope: the branch files (crates/worker/**), plan.md and phase-03 file of the M1 plan, the two reports.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- No deploy, no Cloudflare secret changes, no Supabase schema changes. Never print keys or tokens.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names
  (the plan.md status table itself is fine). `git add` explicit paths only. No GitHub.
- Do not touch m1-server-p01-cook's branch or worktree. Stop every process you start; leave other projects'
  wrangler/workerd processes alone (port 8787 belongs to another project).
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261123-m1-p03.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, fix commit SHAs, plan-status SHA, findings and fixes,
test/build/clippy results on main, worktree/branch removal, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
