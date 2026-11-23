# Brief: m1-server-p05-cook

You are session "m1-server-p05-cook". Your only job: implement Phase 5 of the M1 plan with `/ak-cook`: deploy the
merged Worker with two real tokens, remove SPIKE_TOKEN, write and run the acceptance script on the deployed Worker,
update measure-worker.sh, and update the docs. You do NOT merge: "m1-server-p05-review" reviews and merges.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md (six acceptance criteria), phase-05-deploy-va-nghiem-thu.md
  (your exact task list), phase-01..04 (all Completed), docs/architecture.md, docs/roadmap.md, docs/prd.md §11,
  scripts/measure-worker.sh, crates/worker/src/*.rs, crates/cli/src/*.rs, crates/worker/wrangler.toml, and the
  reports plans/reports/{cook,review}-261123-m1-p0{1,2,3,4}.md.
- State: main is at adf07f3 (Phases 1-4 merged). `cargo test --workspace` → cli 23, envelope 7 + 26, worker 35.
  The Supabase migration 20261123000000 (anon reads events only, Realtime publication, pg_cron purge) is live on
  project gykrhmpliphrcpiryzuq (URL https://gykrhmpliphrcpiryzuq.supabase.co).
- The deployed Worker https://os-widget.longdaobk17.workers.dev still runs the M0 code with SPIKE_TOKEN and
  SUPABASE_SERVICE_ROLE_KEY. wrangler: always `npx wrangler@4.166.0`. Supabase CLI 2.122.0 (do not upgrade).
- Operator decision D1 (2026-11-23 09:29), verbatim answer "Cho phép, Keychain (Đề xuất)". It covers exactly:
  generate PUBLISH_TOKEN and CLIENT_TOKEN with `openssl rand -hex 32`; store them in macOS Keychain under services
  `os-widget-publish-token` and `os-widget-client-token`; pipe them straight into `wrangler secret put` without
  writing any file; redeploy the Worker; then delete SPIKE_TOKEN. Nothing else on Cloudflare or Supabase.
- Operator decision (plan validation, 2026-11-23): default ttl 7 days.
- Known follow-ups you must NOT fix here (logged by the supervisor): uppercase UUID → 404, CLI redirect handling,
  envelope URL prefix check. Mention them only if they make a criterion fail.

Work
1. `git worktree add ../os-widget-acceptance -b server-acceptance-docs` from main; scripts and docs work happens
   there. The deploy uses the merged Worker code (identical on your branch: do not touch crates/**).
2. Tokens, per D1. First check `security find-generic-password -s os-widget-publish-token` and
   `-s os-widget-client-token`: if either already exists, stop and SendMessage the supervisor (do not overwrite).
   Otherwise, for each token, in one shell command with no echo:
   `T=$(openssl rand -hex 32) && security add-generic-password -s <service> -a os-widget -w "$T" && printf %s "$T" | npx wrangler@4.166.0 secret put <NAME>; unset T`
   run from crates/worker. Verify by reading back only the length (`security find-generic-password -s <service> -w | wc -c` → 64 plus newline).
3. `npx wrangler@4.166.0 deploy` from crates/worker; record the total and gzip size lines and the version id.
   Quick smoke: GET /items with CLIENT_TOKEN → 200 (pass the header via a chmod 600 temp file, as measure-worker.sh does).
   Only after the new version answers: `npx wrangler@4.166.0 secret delete SPIKE_TOKEN` (non-interactive form),
   then `secret list` shows PUBLISH_TOKEN, CLIENT_TOKEN, SUPABASE_SERVICE_ROLE_KEY and no SPIKE_TOKEN.
4. Write `scripts/acceptance-server.sh <worker-url>` exactly per phase-05 (six criteria + limit checks + 7-day
   default ttl check + cleanup DELETE of every item it created; test items use source "acceptance" and ttl 3600
   except the one checking the default ttl). Tokens and SUPABASE_ANON_KEY come from the environment; set them at
   run time from Keychain and from `supabase projects api-keys --project-ref gykrhmpliphrcpiryzuq -o json | jq`
   (the publishable `sb_publishable_...` key; legacy anon JWT keys are disabled). Never print any of them.
   `shellcheck` it if available.
5. Run it on the deployed Worker; save the output (no tokens or keys) to
   plans/261123-0159-m1-server/reports/acceptance.md with date, Worker version id and key type used.
6. Update scripts/measure-worker.sh per phase-05 (PUBLISH_TOKEN for POST, CLIENT_TOKEN for GET, max seq from
   GET /items) and run it with count 10 just to prove it works; clean up what it creates if it leaves items.
7. Docs per phase-05: architecture.md §3.1, §3.2, §4.1, §4.2, §4.3, §5 and header lines; roadmap.md "Kết quả" for
   Giai đoạn 1 linking the acceptance report and the ttl decision moved to "Đã chốt"; prd.md §11 câu 3.
   Every new claim must match the code and the script output.
8. Commit on the branch (conventional commits, separate commits for scripts and docs). Do not mark Phase 5 in the
   plan: the review does that.

Checks
- `scripts/acceptance-server.sh` prints six PASS (plus the extra checks) and exits 0 on the deployed Worker.
- `npx wrangler@4.166.0 secret list` as in step 3.
- `cargo test --workspace` still passes (paste counts).
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|sb_publishable_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'` empty;
  `git grep -n SPIKE_TOKEN -- scripts crates` empty.
- No temp header files left; `pgrep -fl "wrangler|workerd"` shows nothing you started.

Rules
- Write scope: the worktree ../os-widget-acceptance (scripts/acceptance-server.sh, scripts/measure-worker.sh,
  docs/architecture.md, docs/roadmap.md, docs/prd.md, plans/261123-0159-m1-server/reports/acceptance.md), your
  report. Do not edit crates/**, supabase/**, plan.md or phase files.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- Cloudflare/Supabase actions allowed: only those in steps 2, 3, 5, 6 and reading the publishable key. No schema
  change, no other secret change, no deletion of data except DELETE calls on items your own runs created.
- Never print or write tokens, keys or passwords (not in logs, reports, commit messages or the terminal).
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names
  (docs may name roadmap stages as they already do). `git add` explicit paths only. No GitHub.
- If a criterion fails because of Worker or CLI code, do not fix crates/**: record it, SendMessage the
  supervisor with the evidence and your recommendation, and keep going with the rest.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261123-m1-p05.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, commits, deploy version id and size, secret list
names, acceptance results per criterion, measure-worker result, docs changed, cleanup, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
