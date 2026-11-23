# Brief: m1-server-p01-review

You are session "m1-server-p01-review". Your only job: review branch `supabase-access-cleanup` with
`/ak-code-review`, merge it `--no-ff` into `main` locally, record the phase status, and remove the worktree and
branch. The migration is ALREADY applied to the live project, so you do not edit it (see Rules).
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-01-schema-supabase.md, phase-03-worker-api-hai-token.md
  (the Worker uses the service role key), phase-05-deploy-va-nghiem-thu.md (criterion 6: anon reads events only),
  docs/architecture.md §5 and §7, supabase/migrations/20261122000000_*.sql (M0 schema),
  plans/reports/cook-261123-m1-p01.md.
- State: main is at 0d7fa55 (Phases 2, 3, 4 merged). `cargo test --workspace` on main → cli 23, envelope 7 + 26,
  worker 35. Branch supabase-access-cleanup is at b9aa56d (one commit on 3bf4580, only
  supabase/migrations/20261123000000_access_realtime_cleanup.sql, 78 lines) in worktree
  /Users/onedayin20902/personal/os-widget-access-cleanup.
- The cook pushed it to project gykrhmpliphrcpiryzuq; the supervisor checked `supabase migration list --linked`
  shows 20261122000000 and 20261123000000 on both sides. The cook's local and remote checks are in its report.
- Operator decisions: D1 (2026-11-23 09:29) "Cho phép, Keychain (Đề xuất)" allowed this one db push only.
  D2 (09:35) "Tôi dọn volume cũ": no session deletes Docker data.

Work
1. Review the migration against phase-01 and architecture §5/§7: revoke/grant order, policy, publication
   idempotence, purge_old_rows (security definer, empty search_path, fully-qualified names, the three deletes and
   30-day retention independent of ttl, events referencing items: check delete order vs. foreign keys), execute
   revokes, pg_cron schedule idempotence if re-run, and that the service role Worker paths (insert/select/update
   on items and events) are unaffected.
2. Read-only remote checks are allowed if you need evidence (DB password from Keychain service
   os-widget-supabase-db via SUPABASE_DB_PASSWORD, never printed). No writes to the live database.
3. A finding that needs SQL changes: do NOT edit the applied migration file. Write it in your report as a
   follow-up migration proposal and SendMessage m0-supervisor; it needs an operator decision before any push.
   Comment or typo-only fixes in the migration file are also not allowed (the applied file must match).
4. Merge from the main worktree: `git merge --no-ff supabase-access-cleanup`.
5. Mark Phase 1 Completed in plan.md's Phases table and phase-01 frontmatter status (tick its checkboxes);
   commit on main `docs: record supabase access progress in plan`, with plans/reports/cook-261123-m1-p01.md and
   your review report added in that commit.
6. `git worktree remove ../os-widget-access-cleanup` and `git branch -d supabase-access-cleanup`.

Checks (on main after the merge)
- `cargo test --workspace` passes (paste counts; cli 23, envelope 7 + 26, worker 35).
- `git ls-files supabase/migrations` shows both migrations.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'` empty.
- `git log --oneline --graph -5 main` shows the merge commit with two parents.

Rules
- Write scope: plan.md and the phase-01 file of the M1 plan, the two reports. Nothing else.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- No db push, no schema or data change on the project, no deploy, no Cloudflare actions, no Docker data deletion.
  Do not start Docker or local Supabase unless a check truly needs it; if you do, stop both at the end.
  Never print keys, passwords or connection strings.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names
  (the plan.md status table itself is fine). `git add` explicit paths only. No GitHub.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261123-m1-p01.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, plan-status SHA, findings (and any follow-up migration
proposal), test results on main, worktree/branch removal, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
