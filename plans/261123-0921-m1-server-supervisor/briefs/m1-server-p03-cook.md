# Brief: m1-server-p03-cook

You are session "m1-server-p03-cook". Your only job: implement Phase 3 (Worker with five endpoints and two
tokens) of the M1 plan with `/ak-cook`, on its own branch and worktree. You do NOT merge and you do NOT
deploy: "m1-server-p03-review" reviews and merges; Phase 5 deploys.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-03-worker-api-hai-token.md, phase-02 (done),
  phase-05-deploy-va-nghiem-thu.md (its acceptance script will exercise your endpoints), docs/architecture.md
  §3, §4.1–§4.3, §5, §7, crates/worker/src/lib.rs, crates/envelope/src/*.rs, plans/reports/review-261123-m1-p02.md.
- State: main is at 280c55e; `cargo test --workspace` → envelope 7 unit + 26 integration, worker 0.
  `envelope::parse(&[u8]) -> Result<Envelope, EnvelopeError{field, message}>` is merged.
- From the envelope review: switch the Worker to `envelope::parse` and keep storing the re-serialized body
  (`serde_json::to_value(&envelope.content)`), never the raw request JSON.
- Operator decisions: plan validation (2026-11-23): default `ttl` = 7 days. D1 (2026-11-23 09:29):
  "Cho phép, Keychain (Đề xuất)" — covers Phase 1 db push and Phase 5 secrets/deploy; it does NOT cover a deploy
  from this session.
- Supabase project gykrhmpliphrcpiryzuq (URL https://gykrhmpliphrcpiryzuq.supabase.co). The deployed Worker still
  runs the M0 code with SPIKE_TOKEN; leave it alone. wrangler: always `npx wrangler@4.166.0`.
- For `wrangler dev`: put SUPABASE_SERVICE_ROLE_KEY into crates/worker/.dev.vars by piping
  `supabase projects api-keys --project-ref gykrhmpliphrcpiryzuq -o json | jq ...` (same key type the Worker uses
  today), plus throwaway PUBLISH_TOKEN/CLIENT_TOKEN from `openssl rand -hex 32`. Never print them.
  Check `git check-ignore crates/worker/.dev.vars` first. Delete .dev.vars at the end.
- Running in parallel:
  - m1-server-p01-cook: branch supabase-access-cleanup (supabase/migrations only). The remote migration may land
    while you test; it only changes anon grants, Realtime and a cron job, so the service-role Worker is unaffected.
  - m1-server-p04-cook: branch cli-publish (crates/cli/**, root Cargo.toml members, Cargo.lock).
  Shared files: root Cargo.toml and Cargo.lock. Whichever review merges second resolves the conflict there.

Work
1. `git worktree add ../os-widget-worker-api -b worker-api-two-tokens` from main; work only there.
2. Implement phase-03 exactly: module split (lib.rs router only; auth.rs, supabase.rs, items.rs, events.rs),
   two tokens with constant-time compare and the 401/403 table, `{error, field, message}` errors, POST /items
   with dedupe (201 new / 200 existing, even if soft-deleted), DEFAULT_TTL_SECS = 7 days, keep the M0 ttl range
   check, GET /items `{seq, items}` with seq read first, GET /events since+limit (default 100, cap 100, <1 or
   non-number → 400 "invalid limit") with item embedding and `item: null`, PATCH read/unread and DELETE with the
   204/404 rules, UUID-only path ids (else 404).
3. Pure logic separated from I/O with unit tests for every case in phase-03 Tasks.
4. The `wrangler dev` round from phase-03 against the project; record each status code and event type in the
   report; soft-delete (DELETE endpoint) the test items afterwards.
5. Out of scope: deploy, secrets on Cloudflare, scripts/, docs/, crates/cli, the plan files.

Checks
- `cargo test -p os-widget-worker` and `cargo test --workspace` pass (paste counts).
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` succeeds; also run
  `worker-build --release` (as wrangler does) and report the bundle size.
- `cargo clippy --workspace --all-targets -- -D warnings` clean.
- `git grep -n SPIKE_TOKEN -- crates` prints nothing on the branch.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'` prints nothing;
  .dev.vars deleted and never staged.
- `pgrep -fl "wrangler|workerd"` shows nothing you started.

Rules
- Write scope: the worktree ../os-widget-worker-api (crates/worker/**, Cargo.lock if a dependency is needed),
  your report. Do not edit docs/, scripts/, supabase/, crates/envelope (if the envelope API is missing something,
  SendMessage the supervisor), plan or phase files.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- Never print or write keys or tokens outside .dev.vars.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names.
  `git add` explicit paths only. No GitHub.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261123-m1-p03.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, commits, test counts, build/bundle size, clippy,
the wrangler dev round results (status codes and events, no secrets), cleanup, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
