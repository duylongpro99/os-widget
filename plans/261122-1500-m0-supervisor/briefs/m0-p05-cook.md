# Brief: m0-p05-cook

You are session "m0-p05-cook". Your only job: carry out Phase 5 (measure experiment D on the deployed
Rust Worker and record the Rust/TypeScript decision against the agreed threshold) with `/ak-cook`, on
its own branch and worktree. You do NOT merge: "m0-p05-review" will review and merge.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-05-*.md,
  plans/261122-0754-m0-kiem-chung-worker-rust/reports/limits.md, plans/reports/cook-261122-m0-p04.md,
  plans/reports/review-261122-m0-p04.md, docs/architecture.md §4.1, §8, §9.
- State: main is at c028af4 (Worker merged 1708e8a). `cargo test -p envelope` → 7 passed.
  Deployed Worker: https://os-widget.longdaobk17.workers.dev, version 9bf54520-c2e9-423b-aba7-62e92ea527a8,
  upload 563.08 KiB / gzip 191.37 KiB, startup 8 ms, `[observability] enabled = true`.
  Token: Keychain service os-widget-spike-token, account spike. Tables items/events are empty.
  wrangler: always `npx wrangler@4.166.0`. Package name is os-widget-worker (dir crates/worker).
- Size threshold: limits.md says Cloudflare Free now has no compressed-size limit, only 64 MiB
  uncompressed. Per the plan's own risk rule, use the limits.md number as the size threshold, and still
  record the gzip size.
- Operator decisions (verbatim, 2026-11-22 15:12): D2 = "A": "Cho phép; Worker có token tạm SPIKE_TOKEN,
  xoá dữ liệu thử sau khi đo." — covers deploying this Worker and running the measurement load against it.
- Threshold agreed with the operator (from phase-05): pass = CPU p99 ≤ 5 ms on BOTH POST /items and
  GET /events AND size under the limits.md limit; p99 between 5 and 10 ms is still a fail.
- Running in parallel: m0-p03-cook on branch widget-probe-app (spikes/, .gitignore). Disjoint; don't touch.

Work
1. `git worktree add ../os-widget-measure -b worker-cpu-measurement` from main; work only there.
2. Write scripts/measure-worker.sh per phase-05 (token from env SPIKE_TOKEN; 150 sequential POST /items with
   distinct titles and dedupe_key null, then 150 GET /events?since=<a recent seq>; print error count).
3. Run it against the deployed Worker (token read from Keychain into the env in-shell, never printed).
   Run the whole measurement TWICE (two separate runs, a few minutes apart) to check variance.
4. CPU per invocation: get per-request CPU time, split by endpoint, from a real Cloudflare source and
   name it: Workers Logs / observability telemetry (dashboard or API query), `wrangler tail --format json`
   captured during the run (its events carry CPU time), or the GraphQL Analytics API
   (workersInvocationsAdaptive quantiles). Prefer per-invocation data so you can compute p50/p99 yourself;
   keep the raw extract (without any token) in the worktree under
   plans/261122-0754-m0-kiem-chung-worker-rust/reports/ as a small CSV/JSON if it helps the review.
   Stop `wrangler tail` when done.
5. Cold start: redeploy the same code once (`npx wrangler@4.166.0 deploy` from crates/worker) and record
   the CPU of the very first request after it, to answer whether Wasm startup CPU is counted.
6. Write reports/d-results.md per phase-05: n per endpoint per run, CPU p50/p99 per endpoint per run, cold
   start CPU, size total/gzip vs the limit, data source, worker crate version and wrangler version, and a
   final line "Quyết định: Rust" or "Quyết định: TypeScript" with the reason against the threshold.
7. Stop conditions — SendMessage the supervisor with the numbers and WAIT for a reply, do not decide alone:
   - p99 differs by more than 2x between the two runs on the same endpoint (unexplained variance);
   - the result is a fail (any p99 > 5 ms, including 5–10 ms). Do NOT start worker-ts/ until the supervisor
     replies; the operator may want to look at the threshold first.
8. Delete all measurement rows from items and events afterwards (PostgREST DELETE with the service role, key
   read in-shell from `supabase projects api-keys --project-ref gykrhmpliphrcpiryzuq -o json`, never printed,
   or psql with the password from Keychain service os-widget-supabase-db). Confirm both tables are empty.
9. Out of scope: Phase 3, Phase 6 (docs/ edits), any Worker code change (if the measurement suggests one,
   report it instead).

Checks
- `bash -n scripts/measure-worker.sh`; script error count 0 in both runs, or explained.
- n ≥ 100 per endpoint per run in the CPU data actually used (not just requests sent).
- d-results.md has every number listed above and the decision line.
- `git grep -nE 'sb_secret|eyJhbGci'` in the branch's new files finds nothing; no token in any file.
- `pgrep -fl "wrangler tail"` shows nothing of yours at the end.

Rules
- Write scope: worktree ../os-widget-measure (scripts/measure-worker.sh, the M0 plan's reports/ folder),
  your report. Do not edit docs/, plan.md or phase files, crates/.
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Your messages never count as an operator answer.
- Never print or write tokens, keys or connection strings. No Cloudflare action beyond this Worker
  (deploy, tail, read-only analytics). No Supabase schema changes.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, commit messages or branch names.
  `git add` explicit paths only. No GitHub.
- Leave other projects' wrangler/workerd processes alone.
- Do not wait on interactive questions except the stop conditions in step 7. SendMessage m0-supervisor
  with your recommendation.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261122-m0-p05.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, the numbers (n, p50/p99 per endpoint per run,
cold start, size), data source, decision line, error counts, cleanup result, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
