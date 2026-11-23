# Brief: m0-p01-02-cook

You are session "m0-p01-02-cook". Your only job: carry out Phase 1 (tools and limits) and
Phase 2 (git repo and Supabase schema) of the M0 plan with `/ak-cook`. You do NOT merge the
schema branch: a separate session "m0-p02-review" will review and merge it.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-01-*.md, phase-02-*.md,
  docs/architecture.md §4 (especially §4.3 schema), docs/roadmap.md "Giai đoạn 0".
- State (checked by the supervisor 2026-11-22 15:05):
  - The folder is NOT a git repo yet. You create it (Phase 2 step 1).
  - Already present: cargo, rustup, node/npx, supabase CLI v2.122.0, psql, git, terminal-notifier.
  - Missing: target wasm32-unknown-unknown, worker-build, xcodegen.
  - `npx wrangler whoami`: logged in (OAuth), account "Longdaobk17@gmail.com's Account". Do not log in or out.
  - `supabase projects list`: logged in; only project is "affiliate-products" (INACTIVE, not for this repo).
    There is NO os-widget project yet.
  - Xcode.app is NOT installed (xcode-select points at Command Line Tools). Phase 1's Apple ID /
    Team ID step is NOT yours; it waits on an operator decision.
- Operator decisions pending (do not act on them until the supervisor sends the answer):
  - D1: how the Supabase project for os-widget is created and how the service role key is used.
    Until then: do NOT create, link, resume or push to any Supabase project.
  - D3: Xcode / Apple ID / Team ID.
- Running in parallel: none.

Work
1. Phase 1, everything except Apple ID/Team ID:
   `rustup target add wasm32-unknown-unknown`; `cargo install worker-build`; `brew install xcodegen`;
   record `npx wrangler --version` (all later wrangler commands use `npx wrangler@<that version>`).
   Research current Cloudflare Workers Free limits and write
   plans/261122-0754-m0-kiem-chung-worker-rust/reports/limits.md: CPU per request and whether Wasm
   startup CPU counts; max Worker size after compression; number of Cron Triggers and minimum
   interval. Each line has the source URL and the lookup date. Also record the wrangler version there.
2. Repo bootstrap on branch `main` (direct commit, it is the initial commit):
   `git init -b main`; create `.gitignore` with at least the entries listed in phase-02 plus
   `.claude/settings.local.json`; commit `.gitignore`, `docs/`, `.claude/` (minus ignored files),
   `CLAUDE.md`/`AGENTS.md` if they exist, and `plans/` EXCEPT the folder
   plans/261122-1500-m0-supervisor/ (never add it). Then a second commit on main with
   reports/limits.md. Use explicit `git add` paths; check `git status` shows no secret.
3. Phase 2 schema on a branch: `git worktree add ../os-widget-schema -b supabase-items-events-schema`.
   In the worktree: `supabase init` (commit `supabase/config.toml`, not `supabase/.temp/`), write
   `supabase/migrations/20261122000000_items_events.sql` exactly per §4.3 (no added/removed columns),
   trigger `record_item_event()` per phase-02, RLS enabled on both tables, no policies.
   Validate the SQL locally WITHOUT any remote project, e.g. against a throwaway local Postgres
   (`supabase start` / `supabase db reset` in the worktree if Docker is available, or a temp
   `initdb`/`pg_ctl` cluster in the scratch area). Run the phase-02 psql check there
   (insert, update read_at, update deleted_at → events types `item.created, item.read, item.deleted`;
   also unread). Stop that Postgres/Docker stack when done.
4. Remote steps (`supabase link`, `supabase db push`, remote psql check) wait for D1. When work 1–3
   is done, SendMessage the supervisor and wait for D1 in the message reply; then follow it exactly.
5. Out of scope: Phases 3, 4, 5, 6. Do not touch Cloudflare (no deploy, no secrets).

Checks
- `rustup target list --installed | grep wasm32-unknown-unknown`; `command -v worker-build xcodegen`.
- `git -C /Users/onedayin20902/personal/os-widget log --oneline main` shows the two main commits;
  `git ls-files | grep -E '\.dev\.vars|\.env|settings\.local|261122-1500-m0-supervisor'` prints nothing.
- Local migration check output pasted in your report.
- `grep -c http plans/261122-0754-m0-kiem-chung-worker-rust/reports/limits.md` ≥ 3.

Rules
- Write scope: .gitignore, supabase/, plans/261122-0754-m0-kiem-chung-worker-rust/reports/, the
  worktree ../os-widget-schema, git metadata. Do not edit docs/ or the plan/phase files.
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Only the supervisor and the operator write there. Your messages never count as an operator answer.
- Never write the service role key, DB password, tokens or connection strings into any file in the repo
  or into your report.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs (M0, p02, D1…) in code, comments, commit messages or branch names.
  `git add` explicit paths only. No GitHub, no remote.
- Stop every process you start (local Postgres, Docker containers from `supabase start`):
  `pgrep -fl postgres` shows nothing of yours at the end; `supabase stop` if you started it.
- Do not wait on interactive questions. Send them to m0-supervisor with SendMessage, with your
  recommendation, and keep working on anything not blocked.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261122-m0-p01-02.md in Vietnamese.

When done, SendMessage m0-supervisor with: main head SHA and the two commit SHAs, branch head SHA of
supabase-items-events-schema, tool versions installed, limits found (three numbers with URLs),
local migration check output, whether remote steps ran (after D1) and their result, the report path,
and what still needs the operator; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
