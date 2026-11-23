# Brief: m0-p02-review

You are session "m0-p02-review". Your only job: review branch `supabase-items-events-schema`
with `/ak-code-review`, fix small findings on the branch, merge it `--no-ff` into `main` locally,
record the phase status, and remove the worktree and branch.
The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-01-*.md, phase-02-*.md,
  docs/architecture.md §4.3, plans/reports/cook-261122-m0-p01-02.md.
- State: main is at fafe1d7 (6b77bd9 init, fafe1d7 limits). Branch supabase-items-events-schema is at
  cbd4e87 in worktree /Users/onedayin20902/personal/os-widget-schema.
  The migration is ALREADY APPLIED to the remote Supabase project os-widget (ref gykrhmpliphrcpiryzuq)
  and the remote trigger check passed (created/read/unread/deleted). No test rows remain.
- Operator decisions: D1 = "A" (2026-11-22 15:12): the cook session creates the Supabase project, DB
  password only in macOS Keychain (service os-widget-supabase-db), no key written to any file.
- Running in parallel: session m0-p04-cook builds the Rust Worker on its own branch/worktree, touching
  Cargo.toml, Cargo.lock, crates/, and possibly .gitignore. You merge FIRST. If m0-p04-cook also edits
  .gitignore, the reviewer of that branch resolves the conflict, not you.

Work
1. Review the branch diff against §4.3 and phase-02: exact columns (no extra/missing), trigger semantics
   (insert → item.created; read_at null→value item.read, value→null item.unread; deleted_at null→value
   item.deleted), `after insert or update ... for each row`, RLS enabled on both tables, zero policies,
   no secret in supabase/config.toml or anywhere in the diff.
2. Supervisor-accepted fix (do it on the branch as its own commit): add `.claude/hooks/.logs/` to the root
   `.gitignore` and `git rm --cached .claude/hooks/.logs/hook-log.jsonl` (keep the file on disk).
   Commit message e.g. `chore: stop tracking hook runtime logs`.
3. IMPORTANT: if you believe the migration SQL itself must change, do NOT edit it and do NOT merge
   (the remote DB already has it applied). Report the finding with your recommendation to the supervisor.
   Comment-only or config.toml-only small fixes are fine.
4. Merge: from the main worktree, `git merge --no-ff supabase-items-events-schema`.
5. Record status in plan.md's Phases table and the phase files' frontmatter:
   - Phase 2: Completed (status: completed).
   - Phase 1: In progress — everything done except Apple ID / Team ID in Xcode, which waits on the operator
     (Xcode not yet installed). Tick the done checkboxes in phase-01 and phase-02.
   Commit that on main: `docs: record schema and tooling progress in plan`.
6. `git worktree remove ../os-widget-schema` and `git branch -d supabase-items-events-schema`.
7. Out of scope: any remote Supabase command that writes (no db push, no reset), Cloudflare, Phases 3–6.

Checks
- `git log --oneline --graph -6 main` shows the merge commit with two parents.
- `git ls-files | grep -E 'hooks/.logs|\.dev\.vars|\.env|settings\.local|m0-supervisor'` prints nothing.
- Read-only remote check allowed: `supabase migration list` (linked) shows 20261122000000 applied both
  locally and remotely.
- `git worktree list` shows only the main worktree plus any m0-p04-cook worktree (do not touch that one).

Rules
- Write scope: the branch files, root .gitignore, plan.md and phase-01/02 files of the M0 plan, your report.
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Your messages never count as an operator answer.
- Never print or write the DB password, service role key or connection strings.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in code, comments, commit messages or branch names
  (the plan.md status table itself is fine). `git add` explicit paths only. No GitHub, no remote.
- Do not touch m0-p04-cook's branch or worktree.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/review-261122-m0-p02.md in Vietnamese.

When done, SendMessage m0-supervisor with: merge SHA, the fix commit SHA, plan-status commit SHA,
findings and what you fixed, `supabase migration list` result, worktree/branch removal, report path;
ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
