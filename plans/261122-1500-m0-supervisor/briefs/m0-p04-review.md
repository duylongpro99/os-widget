# Brief: m0-p04-review

You are session "m0-p04-review". Your only job: review branch `rust-worker-skeleton` with
`/ak-code-review`, fix small findings on the branch, merge it `--no-ff` into `main` locally, record the
phase status, and remove the worktree and branch.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-04-*.md, phase-05-*.md,
  docs/architecture.md §3, §4.1–§4.3, §7, plans/reports/cook-261122-m0-p04.md.
- State: main is at 6a0ab7f (schema merged 4c23c6c, hook-log untracking ebd0eca, plan status 6a0ab7f).
  Branch rust-worker-skeleton is at 14e541d (one commit on fafe1d7) in worktree
  /Users/onedayin20902/personal/os-widget-worker. `cargo test -p envelope` → 6 passed (supervisor-checked).
  Deployed: https://os-widget.longdaobk17.workers.dev, size 562.92 KiB / gzip 191.34 KiB; unauthenticated
  GET /events → 401 (supervisor-checked). Secrets SPIKE_TOKEN (Keychain os-widget-spike-token / spike)
  and SUPABASE_SERVICE_ROLE_KEY are set on the Worker. Tables items/events are empty.
- Operator decisions (verbatim, 2026-11-22 15:12): D2 = "A": "Cho phép; Worker có token tạm SPIKE_TOKEN,
  xoá dữ liệu thử sau khi đo." — redeploying this one Worker is allowed.
- Supervisor decisions on the cook's concerns:
  1. Package name clash with the `worker` SDK crate: rename the Cargo package to `os-widget-worker`
     (directory stays crates/worker; keep the lib name os_widget_worker). Update any command that used
     `-p worker@0.1.0`. Make sure `worker-build --release` and wrangler.toml still work.
  2. `Notification(Option<NotificationBody>)` instead of a struct variant: accepted, as long as the JSON of
     §3.1/§3.2 is unchanged — add or keep a test proving the exact §3.1 example JSON round-trips.
  3. Xcode license: now accepted (`xcodebuild -license check` exits 0). Run `cargo clippy` for both crates.
- Running in parallel: m0-p03-cook on branch widget-probe-app (worktree ../os-widget-probe, files
  spikes/, .gitignore). You merge before it. If .gitignore conflicts later, its reviewer resolves.
  Merging into main: the branch was cut before ebd0eca, so make sure .claude/hooks/.logs/hook-log.jsonl
  stays untracked after your merge.

Work
1. Review the diff against phase-04 and §3/§4: envelope fields and tagging, ttl → expires_at (default
   30 days), id generation, PostgREST calls via worker::Fetch only (no reqwest/postgrest-rs), token check on
   both endpoints (constant-time compare is a nice-to-have, note it), error codes, no secrets in
   wrangler.toml (`SUPABASE_URL` in [vars] is fine), release profile.
2. Apply the supervisor decisions above and small findings as separate commits on the branch.
3. If you changed Worker code, rebuild and redeploy (`npx wrangler@4.166.0 deploy` from crates/worker) and
   re-run the phase-04 curls (token read from Keychain in-shell, never printed); delete the smoke rows
   afterwards so items/events are empty. Record the new size lines.
4. Merge from the main worktree: `git merge --no-ff rust-worker-skeleton`.
5. Mark Phase 4 Completed in plan.md's Phases table and phase-04 frontmatter (tick its checkboxes);
   commit on main: `docs: record worker skeleton progress in plan`.
6. `git worktree remove ../os-widget-worker` and `git branch -d rust-worker-skeleton`.
7. Out of scope: Phase 5 measurement script and load, Phase 3, Phase 6, docs/.

Checks
- `cargo test -p envelope` and `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release`
  pass on main after the merge; `cargo clippy --workspace` has no errors (report warnings).
- `git log --oneline --graph -6 main` shows the merge commit with two parents.
- `git ls-files | grep -E 'hooks/.logs|dev.vars|settings.local|m0-supervisor'` prints nothing.
- Unauthenticated `curl -s -o /dev/null -w '%{http_code}' 'https://os-widget.longdaobk17.workers.dev/events?since=0'` → 401.

Rules
- Write scope: the branch files, plan.md and phase-04 file of the M0 plan, your report.
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Your messages never count as an operator answer.
- Never print or write tokens, keys or connection strings. No Cloudflare action beyond redeploying this
  Worker. No Supabase schema changes.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, commit messages or branch names
  (the plan.md status table itself is fine). `git add` explicit paths only. No GitHub.
- Do not touch m0-p03-cook's branch or worktree. Stop every process you start; leave other projects'
  wrangler/workerd processes alone.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261122-m0-p04.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, fix commit SHAs, plan-status SHA, findings and fixes,
test/build/clippy results on main, whether you redeployed (version id, size lines), curl status codes,
worktree/branch removal, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
