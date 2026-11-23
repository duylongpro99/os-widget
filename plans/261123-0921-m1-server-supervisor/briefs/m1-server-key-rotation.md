# Brief: m1-server-key-rotation

You are session "m1-server-key-rotation". Your only job: rotate the Supabase secret API key the Worker uses
(Cloudflare secret SUPABASE_SERVICE_ROLE_KEY), prove the Worker still works, then revoke the old key. No code
changes, no commits. The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read: docs/architecture.md §4.3 and §7, crates/worker/src/supabase.rs (how the key is sent), crates/worker/wrangler.toml,
  scripts/acceptance-server.sh, plans/reports/review-261123-m1-p05.md.
- State: main is at 6d27b32; M1 is completed. Worker https://os-widget.longdaobk17.workers.dev, active version
  29517735, secrets CLIENT_TOKEN, PUBLISH_TOKEN, SUPABASE_SERVICE_ROLE_KEY. Supabase project gykrhmpliphrcpiryzuq.
  The Worker's key is a new-style `sb_secret_...` key (legacy JWT keys are disabled on the project).
- Why: an earlier session printed the first 15 characters of that key into its own transcript.
- Operator decision D4 (2026-11-23 13:29), verbatim answer "Xoay khoá sau khi merge": create a new secret key on
  Supabase, pipe it into `wrangler secret put SUPABASE_SERVICE_ROLE_KEY`, check the Worker, then revoke the old key.
  Operator decision D3 (11:5x) "Tôi bấm Allow (Đề xuất)": the Supabase CLI may read its login token from Keychain.
  If the CLI says "Access token not provided", you may read the same "Supabase CLI" Keychain item with `security`
  into SUPABASE_ACCESS_TOKEN for that one command (never printed), as the Phase 5 reviewer did.
- wrangler: always `npx wrangler@4.166.0`, run from crates/worker. Supabase CLI 2.122.0 (do not upgrade).

Work
1. List the project's API keys WITHOUT printing key values: only id, name and type (filter with jq to those
   fields). If there is exactly one key of type `secret`, that is the old key the Worker uses. If there are
   several, SendMessage the supervisor with their ids and names (no values) and wait.
2. Create a new secret key (Supabase CLI if 2.122.0 supports it, otherwise the Management API
   `POST https://api.supabase.com/v1/projects/gykrhmpliphrcpiryzuq/api-keys` with body {"type":"secret","name":"os-widget-worker-<yyyymmdd>"}
   and the access token in a header file chmod 600). Capture the new value straight into a pipe:
   `... | jq -r .api_key | npx wrangler@4.166.0 secret put SUPABASE_SERVICE_ROLE_KEY` — never into a file or the terminal.
   If the API returns the key only in a response you must store, use a shell variable, then `unset` it.
3. Check the Worker on the new key: run `scripts/acceptance-server.sh https://os-widget.longdaobk17.workers.dev`
   (tokens from Keychain, SUPABASE_ANON_KEY = publishable key read the same non-printing way). It must pass all
   checks and clean up its items. Record the new active Worker version id.
4. Only after step 3 passes: revoke/delete the OLD secret key (by id). Then re-run a quick check: GET /items with
   the client token → 200, POST nothing. If step 3 fails, do NOT revoke; SendMessage the supervisor with the error.
5. Final key list (ids, names, types only) shows exactly one secret key: the new one.

Checks
- `npx wrangler@4.166.0 secret list` still shows CLIENT_TOKEN, PUBLISH_TOKEN, SUPABASE_SERVICE_ROLE_KEY.
- Acceptance output: every check PASS, exit 0, no items left (GET /items count 0 for source acceptance).
- No temp files with secrets left; `git status --short` shows no new tracked or untracked files from you except your report.

Rules
- Write scope: your report only. No commits needed; do not stage anything.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- Allowed live actions: exactly steps 1-5. No other secret, key, schema or data changes; no deploy of new code.
- Never print any key, token or password, in full or in part (no prefixes, no lengths of secret values beyond
  "present/absent", no `head -c`). Check key types by the `type` field only.
- Stop every process you start; other projects' wrangler/workerd processes are not yours.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/ops-261123-m1-key-rotation.md in Vietnamese (no secret values).

When done, SendMessage m0-supervisor with: old key id/name revoked, new key id/name, new active Worker version,
acceptance results, final key list (no values), report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
