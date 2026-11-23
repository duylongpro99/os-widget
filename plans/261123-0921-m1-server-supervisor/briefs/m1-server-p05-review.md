# Brief: m1-server-p05-review

You are session "m1-server-p05-review". Your only job: review branch `server-acceptance-docs` with
`/ak-code-review`, fix small findings on the branch, re-run the acceptance script once on the deployed Worker,
merge `--no-ff` into `main` locally, record the phase and plan status, and remove the worktree and branch.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md (six acceptance criteria), phase-05-deploy-va-nghiem-thu.md,
  plans/reports/cook-261123-m1-p05.md, the branch diff, crates/worker/src/*.rs and crates/cli/src/*.rs (to check
  docs claims against code), supabase/migrations/20261123000000_access_realtime_cleanup.sql.
- State: main is at adf07f3 (Phases 1-4 Completed). `cargo test --workspace` → cli 23, envelope 7 + 26, worker 35.
  Branch server-acceptance-docs is at c824c63 (14fef50 scripts, c824c63 docs; 6 files: scripts/acceptance-server.sh,
  scripts/measure-worker.sh, docs/architecture.md, docs/prd.md, docs/roadmap.md,
  plans/261123-0159-m1-server/reports/acceptance.md) in worktree /Users/onedayin20902/personal/os-widget-acceptance.
- Deployed: Worker https://os-widget.longdaobk17.workers.dev, active version 29517735 (code version 040e4e09).
  Supervisor-checked: secret list = CLIENT_TOKEN, PUBLISH_TOKEN, SUPABASE_SERVICE_ROLE_KEY; GET /items without
  token → 401, with the client token → 200.
- Operator decisions: D1 (2026-11-23 09:29) "Cho phép, Keychain (Đề xuất)": tokens in Keychain services
  os-widget-publish-token / os-widget-client-token. D3 (11:5x) "Tôi bấm Allow (Đề xuất)": Supabase CLI may read its
  login token from Keychain. Default ttl 7 days (plan validation).

Work
1. Review the diff against phase-05: the script covers every listed check, prints PASS/FAIL with reasons, exits 1
   on any FAIL, header files chmod 600 and removed on exit (trap), no token/key ever echoed (also under `set -x`
   absence, error paths and curl verbose), cleanup deletes every item it creates even on failure, run_id isolation,
   ttl 3600 on test items. measure-worker.sh changes. Docs: every new claim matches code, migration and the
   acceptance output; links resolve; architecture.md stays under 800 lines.
2. Fix small findings as separate commits on the branch. Do not touch crates/** or supabase/**: a code defect goes
   to your report and a SendMessage to the supervisor.
3. Re-run once: tokens from Keychain, SUPABASE_ANON_KEY = the publishable key from
   `supabase projects api-keys --project-ref gykrhmpliphrcpiryzuq -o json | jq` (select type "publishable" only;
   never print any key, not even a prefix), `scripts/acceptance-server.sh https://os-widget.longdaobk17.workers.dev`.
   Paste PASS/FAIL lines in your report. Confirm no test items remain afterwards.
4. Merge from the main worktree: `git merge --no-ff server-acceptance-docs`.
5. Mark Phase 5 Completed in plan.md's Phases table and phase-05 frontmatter (tick its checkboxes), and set the
   plan's own status to completed if plan.md has one. Commit on main `docs: record server acceptance in plan`, with
   plans/reports/cook-261123-m1-p05.md and your review report added in that commit.
6. `git worktree remove ../os-widget-acceptance` and `git branch -d server-acceptance-docs`.

Checks (on main after the merge)
- `cargo test --workspace` passes (paste counts).
- `shellcheck scripts/*.sh` clean (if installed).
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|sb_publishable_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'`
  empty; `git grep -n SPIKE_TOKEN -- scripts crates` empty.
- `git log --oneline --graph -5 main` shows the merge commit with two parents.

Rules
- Write scope: the branch files listed above, plan.md and phase-05 of the M1 plan, the two reports.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- No deploy, no secret changes, no Supabase schema changes, no key rotation. Live calls only through the
  acceptance script run in step 3 (and DELETE of items it created). Never print tokens or keys, in full or in part.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names
  (the plan.md status table itself is fine). `git add` explicit paths only. No GitHub.
- Stop every process you start; other projects' wrangler/workerd processes are not yours.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261123-m1-p05.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, fix commit SHAs, plan-status SHA, findings and fixes,
acceptance re-run results, test results on main, worktree/branch removal, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
