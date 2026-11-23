# Brief: m1-server-p04-cook

You are session "m1-server-p04-cook". Your only job: implement Phase 4 (crate `cli`, binary `os-widget`,
command `publish`) of the M1 plan with `/ak-cook`, on its own branch and worktree. You do NOT merge:
"m1-server-p04-review" reviews and merges.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-04-cli-publish.md, phase-03-worker-api-hai-token.md
  (the server contract: 201/200/400 `{error, field, message}`/401/403), phase-05-deploy-va-nghiem-thu.md
  (its acceptance script calls `cargo run -q -p cli -- publish ...`), docs/architecture.md §3, §4.1, §4.2,
  crates/envelope/src/*.rs, plans/reports/review-261123-m1-p02.md.
- State: main is at 280c55e; `cargo test --workspace` → envelope 7 unit + 26 integration, worker 0.
  `envelope::parse(&[u8]) -> Result<Envelope, EnvelopeError{field, message}>` is merged.
- The Worker with the new contract is not deployed yet (Phase 3 is being written in parallel). Real calls to the
  server happen in Phase 5; test the HTTP-response mapping with pure functions.
- Running in parallel:
  - m1-server-p03-cook: branch worker-api-two-tokens (crates/worker/**, maybe Cargo.lock).
  - m1-server-p01-cook: branch supabase-access-cleanup (supabase/migrations only).
  Shared files: root Cargo.toml and Cargo.lock. Whichever review merges second resolves the conflict there.

Work
1. `git worktree add ../os-widget-cli -b cli-publish` from main; work only there.
2. Implement phase-04 exactly: package name `cli` (so `cargo run -p cli` works) with `[[bin]] name = "os-widget"`;
   deps envelope, serde_json, clap derive, ureq 3 (rustls default; read the docs of the version that lands in
   Cargo.lock, not ureq 2 examples); config from OS_WIDGET_SERVER (overridable by --server) and
   OS_WIDGET_PUBLISH_TOKEN (env only); `--file PATH|-` vs notification flags (conflicts_with); `--link` not `--url`;
   `--dry-run`; the output/exit-code table (0/2/1). Treat any 4xx/5xx as a response to map, not a transport error
   (ureq 3 returns errors for status codes by default; configure that off or handle it).
3. Pure functions + unit tests for every case in phase-04 Tasks.
4. Manual `--dry-run` with a valid vocab file and one missing `definition`; paste outputs and exit codes.
5. Out of scope: Worker, deploy, scripts/, docs/, plan files.

Checks
- `cargo test -p cli` and `cargo test --workspace` pass (paste counts).
- `cargo build -p cli` does not compile `worker` (check `cargo tree -p cli | grep -c '^.*worker '` is 0).
- `cargo clippy --workspace --all-targets -- -D warnings` clean.
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` still succeeds (workspace change).
- `cargo run -p cli -- publish --dry-run --file <broken vocab>` exits 2 and prints `body.meanings[0]`.

Rules
- Write scope: the worktree ../os-widget-cli (crates/cli/**, root Cargo.toml members, Cargo.lock), your report.
  Do not edit crates/envelope (if its API is missing something, SendMessage the supervisor), crates/worker, docs/,
  scripts/, supabase/, plan or phase files.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- No network calls to the deployed Worker; no tokens.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names.
  `git add` explicit paths only. No GitHub.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261123-m1-p04.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, commits, test counts, clippy/build results, the
dry-run outputs and exit codes, ureq version, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
