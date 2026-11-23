# Brief: m1-server-p02-cook

You are session "m1-server-p02-cook". Your only job: implement Phase 2 (envelope with three kinds and
field-path errors) of the M1 plan with `/ak-cook`, on its own branch and worktree. You do NOT merge:
a separate session "m1-server-p02-review" will review and merge.
The supervisor is session "m0-supervisor" (it supervises M1 under that name).

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-0159-m1-server/plan.md, phase-02-envelope-ba-loai.md, phase-03-worker-api-hai-token.md
  and phase-04-cli-publish.md (both consume `envelope::parse` and `EnvelopeError`), docs/architecture.md §3
  (all of it), §7, crates/envelope/src/lib.rs, crates/envelope/Cargo.toml, crates/worker/src/lib.rs (current
  user of the crate).
- State: main is at 3bf4580; `cargo test --workspace` → envelope 7 passed, worker 0.
- Decided in the plan's validation (operator, 2026-11-23): vocab required fields are `word`, `ipa`, `pos`, `meanings`.
- Running in parallel: m1-server-p01-cook on branch `supabase-access-cleanup` (worktree
  ../os-widget-access-cleanup, file supabase/migrations/20261123000000_access_realtime_cleanup.sql). Do not touch it.

Work
1. `git worktree add ../os-widget-envelope -b envelope-three-kinds` from main; work only there.
2. Implement phase-02 exactly: VocabBody, Meaning, GenericBody, Block (seven types), two new Body variants,
   `Body::kind()`, two-step `parse(bytes) -> Result<Envelope, EnvelopeError>` with serde_path_to_error and the
   `body.` prefix, the semantic checks with their `field` values, `Display` as specified, no
   `deny_unknown_fields`, strip "at line X column Y" from messages.
3. One test function per case listed in phase-02 Tasks. Keep every existing test passing unchanged
   (JSON format of §3.1 must not change).
4. The Worker must still compile against the new crate (do not refactor the Worker; Phase 3 does that). If an
   exhaustive match on `Body` breaks the Worker build, make the smallest change in crates/worker/src/lib.rs that
   keeps behaviour, and say so in the report.
5. Out of scope: Phases 1, 3, 4, 5, docs/, plan files.

Checks
- `cargo test -p envelope` passes (paste counts; must be > 7 with all old tests kept).
- `cargo build -p envelope --target wasm32-unknown-unknown --release` succeeds.
- `cargo build -p os-widget-worker --target wasm32-unknown-unknown --release` still succeeds.
- `cargo clippy -p envelope -- -D warnings` clean; `cargo clippy --workspace -- -D warnings` clean or report warnings.
- A flaky test: rerun it alone and report it; do not edit the test to pass.

Rules
- Write scope: the worktree ../os-widget-envelope (crates/envelope/**, Cargo.lock, and only the minimal Worker
  change from step 4), your report. Do not edit docs/, plan or phase files, supabase/.
- Do not write, create or delete anything under plans/261123-0921-m1-server-supervisor/,
  plans/261122-1500-m0-supervisor/ or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, test names, commit messages or branch names.
  `git add` explicit paths only. No GitHub. No deploy.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261123-m1-p02.md in Vietnamese.

When done, SendMessage m0-supervisor with: branch head SHA, commits, test counts, build/clippy results, any
Worker change, the exact public API added (signatures), report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
