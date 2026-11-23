# Brief: m1-server-p01-cook

You are session "m1-server-p01-cook". Your only job: implement Phase 1 (schema access, Realtime,
pg_cron cleanup on Supabase) of the M1 plan with `/ak-cook`, on its own branch and worktree.
You do NOT merge: a separate session "m1-server-p01-review" will review and merge.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-01-schema-supabase.md,
  phase-05-deploy-va-nghiem-thu.md (criterion 6 is re-checked over HTTP there), docs/architecture.md §4.3, §5,
  supabase/migrations/20261122000000_items_events.sql.
- State: main is at 3bf4580; `cargo test --workspace` → envelope 7 passed. The M0 migration is applied on
  project gykrhmpliphrcpiryzuq (URL https://gykrhmpliphrcpiryzuq.supabase.co, not secret). The main worktree
  is NOT supabase-linked. DB password is in macOS Keychain service `os-widget-supabase-db` (read in-shell,
  never print). Supabase CLI 2.122.0 (do not upgrade), psql at /opt/homebrew/opt/libpq/bin/psql.
- Docker Desktop is installed but NOT running. Start it with `open -a Docker` and wait for `docker info`.
  Because you started it, quit it at the end (`supabase stop` first, then `osascript -e 'quit app "Docker"'`).
- Operator decision D1 (remote `supabase db push` of this migration) is still OPEN. Do all local work first.
  Do NOT run `supabase link`/`db push` or any remote change until the supervisor SendMessages you the D1
  answer. If local work finishes before that, SendMessage the supervisor "local done, waiting for D1" and wait.
- Running in parallel: m1-server-p02-cook on branch `envelope-three-kinds` (worktree ../os-widget-envelope,
  files crates/envelope/**, Cargo.lock). Do not touch those.

Work
1. `git worktree add ../os-widget-access-cleanup -b supabase-access-cleanup` from main; work only there.
2. Create supabase/migrations/20261123000000_access_realtime_cleanup.sql exactly per phase-01's design
   (two-layer access, Realtime publication guarded by a pg_publication_tables check, purge_old_rows()
   security definer with `set search_path = ''`, pg_cron schedule `os-widget-purge` at `17 3 * * *`,
   revoke execute from public, anon, authenticated). Comment the reason for each block.
3. Local: `supabase start`, `supabase db reset`, then every psql check listed in phase-01 Tasks
   (anon can select events, cannot select items, cannot call purge_old_rows; purge test with the four rows;
   cron.job has os-widget-purge; publication has events). Paste each query's result into the report.
4. After the D1 answer, and only if it allows it: `supabase link --project-ref gykrhmpliphrcpiryzuq`,
   `supabase db push`, then repeat the cron.job and publication checks (plus the anon role grant check) on
   the project via psql with the password from Keychain. If `create extension pg_cron` fails, SendMessage
   the supervisor with the exact error (the operator must enable it in the dashboard); do not drop the schedule.
5. Out of scope: Phases 2–5, docs/, Worker code, the plan files.

Checks
- `supabase db reset` exits 0 with the new migration.
- All local psql checks give the expected results; same for the remote checks after push.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'` on the branch prints nothing.
- `git status` in the worktree shows no untracked supabase/.temp or connection material committed.
- At the end: `supabase stop` done, Docker quit (you started it), `pgrep -fl "postgres|supabase"` shows
  nothing you started.

Rules
- Write scope: the worktree ../os-widget-access-cleanup (the new migration file only, plus supabase/.gitignore
  if link state must be ignored), your report. Do not edit docs/, plan or phase files, crates/.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- Never print or write passwords, keys or connection strings (not in the terminal, files, commits or report).
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, commit messages or branch names.
  `git add` explicit paths only. No GitHub.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261123-m1-p01.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, commits, local check results, whether the
migration was pushed and the remote check results, cleanup (supabase stop, Docker quit), report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
