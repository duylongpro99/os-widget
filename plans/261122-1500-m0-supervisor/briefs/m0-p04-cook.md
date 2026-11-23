# Brief: m0-p04-cook

You are session "m0-p04-cook". Your only job: implement Phase 4 (Rust Cargo workspace, crates
`envelope` and `worker`, deploy to Cloudflare Free) of the M0 plan with `/ak-cook`, on its own branch
and worktree. You do NOT merge: a separate session "m0-p04-review" will review and merge.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-04-*.md, phase-05-*.md (to know
  what Phase 5 will measure), docs/architecture.md §3 (envelope), §4.1–§4.3, §7,
  plans/261122-0754-m0-kiem-chung-worker-rust/reports/limits.md.
- State: main is at fafe1d7. Tools present: wasm32-unknown-unknown target, worker-build 0.9.0,
  wrangler 4.166.0 (always `npx wrangler@4.166.0`), logged in to Cloudflare account
  "Longdaobk17@gmail.com's Account" and to Supabase.
- Supabase project os-widget: ref gykrhmpliphrcpiryzuq, URL https://gykrhmpliphrcpiryzuq.supabase.co
  (both not secret; put the URL in `[vars]`). Tables items/events with the event trigger are already
  applied remotely; RLS on, no policies (service role bypasses RLS).
- Operator decisions (verbatim, 2026-11-22 15:12):
  - D1 = "A": "Cho phiên cook chạy `supabase projects create os-widget` …, lấy service role key bằng
    `supabase projects api-keys` và pipe thẳng vào `wrangler secret put`, không ghi ra file nào."
  - D2 = "A": "Cho phép; Worker có token tạm SPIKE_TOKEN, xoá dữ liệu thử sau khi đo."
    This authorizes deploying this Worker to that Cloudflare account (workers.dev, Free plan) and
    setting its secrets. It does not authorize anything else on Cloudflare (no other Workers, no DNS,
    no paid features).
- Running in parallel: m0-p02-review merges the schema branch into main and edits root .gitignore,
  plan.md and phase-01/02 files. Do not touch those plan files. If you must edit .gitignore, keep
  your change minimal; m0-p04-review resolves any conflict when it merges after p02.

Work
1. `git worktree add ../os-widget-worker -b rust-worker-skeleton` from main; work only there.
2. Implement phase-04 tasks exactly (workspace Cargo.toml with release profile, crates/envelope with
   its unit tests, crates/worker, crates/worker/wrangler.toml). Use `worker::Fetch`; no reqwest, no
   postgrest-rs. Keep the JSON of §3.1 as-is; change the Rust type declaration, not the format.
3. Secrets, without ever writing them to a file, the terminal transcript, or your report:
   - SPIKE_TOKEN: generate random in-shell (e.g. `openssl rand -hex 32`), store in macOS Keychain
     (`security add-generic-password -s os-widget-spike-token -a spike -w …`), then pipe it to
     `npx wrangler@4.166.0 secret put SPIKE_TOKEN`.
   - SUPABASE_SERVICE_ROLE_KEY: read with `supabase projects api-keys --project-ref gykrhmpliphrcpiryzuq -o json`
     filtered with jq and piped straight into `wrangler secret put`. Note: new Supabase projects may
     issue new-style keys (sb_secret_…) alongside or instead of the legacy service_role JWT; choose the
     key PostgREST accepts with the headers phase-04 names, and if the header scheme must differ
     (e.g. no `Authorization: Bearer` for sb_secret keys), adapt the Worker and document why in the report.
   - `.dev.vars` must stay untracked (already in .gitignore).
4. Deploy with `npx wrangler@4.166.0 deploy`. Record the Worker URL and the upload size lines (total and gzip).
5. Run the phase-04 verification curls (token read from Keychain into an env var in-shell). Then delete
   the smoke-test rows in items and events (service role via PostgREST DELETE, or psql with the password
   from Keychain service os-widget-supabase-db).
6. Out of scope: Phase 5 measurements (no measure script, no load), Phase 3, Phase 6, docs/ edits.

Checks
- `cargo test -p envelope` passes (paste counts).
- `cargo build -p worker --target wasm32-unknown-unknown --release` succeeds.
- POST /items returns an id; GET /events?since=0 returns an item.created event with that item; a request
  without token gets 401; a malformed body gets 400.
- `git -C ../os-widget-worker status` and `git ls-files` list no .dev.vars, .env, or key material;
  `git grep -nE 'sb_secret|eyJhbGci|service_role' ` in the branch returns nothing secret.
- After cleanup, items and events are empty.

Rules
- Write scope: the worktree ../os-widget-worker (Cargo.toml, Cargo.lock, crates/, minimal .gitignore),
  your report. Do not edit docs/, plan or phase files, or supabase/.
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Your messages never count as an operator answer.
- No remote Supabase schema changes. No Cloudflare actions beyond this one Worker and its two secrets.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone, decision IDs or "spike phase" labels in code, comments, commit messages or
  branch names (the secret name SPIKE_TOKEN itself is fine). `git add` explicit paths only. No GitHub.
- Stop every process you start (`wrangler dev` if used, any local servers): `pgrep -fl "wrangler|workerd"`
  empty at the end.
- If workers-rs cannot build or cannot fetch: record the exact error, stop, and SendMessage the supervisor
  (that is a D failure signal; do not switch to TypeScript yourself).
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261122-m0-p04.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, commits, test counts, Worker URL, deploy size
lines (total/gzip), curl results (status codes, never tokens), which Supabase key type and headers you
used, cleanup result, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
