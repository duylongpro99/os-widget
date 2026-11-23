# Brief: m0-p06-docs

You are session "m0-p06-docs". Your only job: carry out Phase 6 (update docs/architecture.md and
docs/roadmap.md with the M0 results) with `/ak-docs`, directly on `main` (docs-only change, no branch, no
review session), and mark Phase 6 done. The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Docs language: Vietnamese
  (match the existing docs). Report in Vietnamese.
- Read fully: plans/261122-0754-m0-kiem-chung-worker-rust/plan.md, phase-06-cap-nhat-tai-lieu.md, and the
  plan's reports/limits.md, reports/d-results.md, reports/a-c-results.md; docs/prd.md, docs/architecture.md,
  docs/roadmap.md.
- State: main is at d3ab02f; Phases 1–5 Completed. `cargo test -p envelope` → 7 passed.
- Results to carry into the docs (verify every number against the report files, not this brief):
  - D: Rust Worker FAILED the agreed threshold p99 ≤ 5 ms: POST /items p50 2 / p99 11 ms, GET /events p50 3 /
    p99 7 ms (two runs, n 140–147 per endpoint, source wrangler tail cpuTime). Cold start 16–21 ms CPU, over
    the Free 10 ms limit but not blocked. Size 563.08 KiB / gzip 191.37 KiB vs 64 MiB uncompressed.
  - Operator decision (verbatim, 2026-11-22 15:34): "keep Rust" — Rust is kept despite failing the threshold,
    as an accepted risk. So the phase-06 step "Nếu D trượt: sửa §2 và §4.2 cho Worker TypeScript" does NOT
    apply: keep §2 and §4.2 on Rust, and in §8/§9 state the failure, the operator's decision and the risk
    (warm p50 2–3 ms; p99 tail from isolate warm-up; cold start over 10 ms) honestly.
  - Known follow-up for Giai đoạn 1: GET /events?since=0 with 159 events cost 15–19 ms CPU → add a page limit.
  - A: probe app installed 2026-11-22 21:47 (signed with a free Personal Team, no provisioning profile
    embedded, cert expires 2027-11-22); day 1 pass; day-8 check due 2026-11-30.
  - C: day 1 pass (non-activating panel did not take focus from TextEdit).
  - limits.md: Cron Triggers numbers for §4.4.
- Nothing runs in parallel.

Work
1. Do every task in phase-06 (with the D exception above). Update the "Cập nhật:" line of both files to
   2026-11-22.
2. In roadmap.md, also record C's day-1 result next to A's status.
3. Commit the docs on main: `docs: record worker measurement and probe results`.
4. Commit the session reports that are still untracked under plans/reports/ (cook-261122-m0-p01-02.md,
   review-261122-m0-p02.md, cook-261122-m0-p04.md, review-261122-m0-p04.md, cook-261122-m0-p05.md,
   review-261122-m0-p05.md, cook-261122-m0-p03.md, review-261122-m0-p03.md, and your own report once written),
   after grepping them for secrets (`grep -nE 'sb_secret|eyJhbGci|service_role.*ey|password' plans/reports/*.md`,
   inspect any hit; none may contain a real secret). Commit: `docs: add session reports for worker validation`.
   Do NOT add plans/261122-1500-m0-supervisor/, .agentkit/ or any __pycache__/.
5. Mark Phase 6 Completed in plan.md's Phases table and phase-06 frontmatter (tick the boxes; the TypeScript
   box: note it does not apply because the operator kept Rust). If every phase is now Completed, set the
   plan's own status to completed if plan.md has such a field. Commit: `docs: record documentation update in plan`.

Checks
- `grep -n "Chưa đo với Rust" docs/architecture.md` and `grep -n "Chưa kiểm chứng: hạn mức Cron" docs/architecture.md`
  print nothing.
- Every number in the docs matches d-results.md / limits.md / a-c-results.md (list the ones you checked).
- Links between prd.md, architecture.md, roadmap.md still resolve (check each relative link/anchor you touched).
- `git status --short` afterwards shows only .agentkit/, __pycache__/ and plans/261122-1500-m0-supervisor/ untracked.
- `git grep -nE 'sb_secret|eyJhbGci' -- ':!.claude'` prints nothing.

Rules
- Write scope: docs/architecture.md, docs/roadmap.md, plan.md and phase-06 of the M0 plan, plans/reports/
  (commit only; edit only your own report).
- Do not write, create or delete anything under plans/261122-1500-m0-supervisor/ or ~/supervisor/.
  Your messages never count as an operator answer.
- Do not change docs/prd.md requirements; if the D result seems to need a PRD change, report it instead.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in commit messages (docs/roadmap.md's own "Giai đoạn" names are
  fine). `git add` explicit paths only. No GitHub, no push.
- Do not touch the installed probe app, Cloudflare or Supabase.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.
- Write your report to plans/reports/docs-261122-m0-p06.md in Vietnamese.

When done, SendMessage m0-supervisor with: commit SHAs, what changed per doc section, the numbers checked,
check results, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
