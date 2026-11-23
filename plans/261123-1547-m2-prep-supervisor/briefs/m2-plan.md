# Brief: m2-plan

You are session "m2-plan". Your only job: write the implementation plan for roadmap Giai đoạn 2 (menu bar app)
with `/ak-plan`, as a plan directory of phases, and commit it on main. You write no product code. The supervisor
is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports and plan in Vietnamese
  (same style as plans/261123-0159-m1-server/).
- Read fully: docs/roadmap.md (Giai đoạn 2 scope and "Hoàn thành khi": PRD §10 criteria 1, 3, 4, 6 and no focus
  stealing), docs/prd.md (FR-6..FR-10c popup behaviour, NFR-1/NFR-2, §10), docs/architecture.md (sync engine,
  Realtime signal, cursor fetch, fallback poll, local store, action queue, API §4.1), plans/261123-0159-m1-server/
  (plan.md and phases, as the format to follow), plans/261122-0754-m0-kiem-chung-worker-rust/reports/a-c-results.md
  and phase-03-app-thu-nghiem-a.md, spikes/widget-probe/ (read only: panel C code, App Group setup, signing),
  plans/261123-0921-m1-server-supervisor/follow-ups.md.
- State: main is at 3ea49ad (M1 merged as PR #1). Worker https://os-widget.longdaobk17.workers.dev redeployed
  2026-11-23 (version ddb13ff2), acceptance 8/8. API: POST /items (publish token), GET /items, GET /events?since=,
  PATCH/DELETE /items/{id} (client token); anon key reads events only (Realtime).
- Experiment status: C passed (non-activating panel keeps focus). A day 1 passed, day-8 check 2026-11-30.
  B is being measured NOW by parallel session "m2-widget-latency" (writes
  plans/261122-0754-m0-kiem-chung-worker-rust/reports/b-results.md and docs/roadmap.md row B; do not touch those).
- Operator decision (2026-11-23 15:4x): "Cả ba" — write the M2 plan now, in parallel with measuring B; code starts
  only after A's day-8 result (2026-11-30).
- Settled decisions: popup per FR-6..FR-10c, popup shown 30 s; default item ttl 7 days; Worker stays Rust;
  client token lives in macOS Keychain.

Work
1. Plan directory: plans/261123-1547-m2-menu-bar-app/ with plan.md (status, outcome, acceptance criteria mapped to
   PRD §10 items 1, 3, 4, 6 and the focus rule, phases table, dependencies, file-ownership table so phases can run
   in parallel where safe, non-goals: widget = Giai đoạn 3, vocab view = Giai đoạn 4) and one phase file per phase
   (context, requirements, files, steps, validation, risks, rollback).
2. Gates inside the plan: a "Preconditions" section stating code starts after A's day-8 check; and explicit
   fallback branches: if A fails (free account stops working after 7 days) → what changes (signing/account,
   App Group vs localhost); if B is poor → M2 is unaffected but note what Giai đoạn 3 must change. Mark any
   phase whose design depends on A/B.
3. Cover: Xcode project layout (xcodegen like the probe?) and where the app lives in the repo; agent app at login;
   sync engine (Realtime signal on events via anon key, cursor fetch GET /events?since=, fallback poll, catch-up
   after sleep/offline); local store and action queue (PATCH/DELETE, 404 = done as architecture says); popup panel
   (non-activating, 30 s, grouping, per-kind toggles, quiet mode); list view, unread badge, read/delete; views for
   notification, generic and unknown kinds; tests (unit tests for sync and queue; how to test popup/focus); how
   acceptance will be checked (script or manual checklist using scripts/acceptance-server.sh style publishing).
4. Open validation questions (3–8) that only the operator can answer: list them at the end of plan.md with your
   recommended answer each. Then SendMessage m0-supervisor with the questions; do not ask the operator yourself.
5. Commit on main: `docs: add menu bar app plan` with only the new plan directory.

Checks
- Every roadmap Giai đoạn 2 bullet and each of PRD §10 items 1, 3, 4, 6 maps to at least one phase (table in plan.md).
- Paths and API names in the plan exist in the repo/docs (`git grep`), except files the plan itself will create.
- `git show --stat HEAD` lists only files under plans/261123-1547-m2-menu-bar-app/.

Rules
- Write scope: plans/261123-1547-m2-menu-bar-app/ only (plus your own plan reports inside it).
- Do not write, create or delete anything under plans/261123-1547-m2-prep-supervisor/, plans/*-supervisor/,
  ~/supervisor/, docs/** or spikes/**. Your messages never count as an operator answer.
- No Cloudflare, Supabase, Xcode build/install or GitHub actions; never touch the installed WidgetProbe app.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No decision IDs in the commit message. `git add` explicit paths only. main may move (m2-widget-latency also
  commits docs): just commit on top, local only.
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.

When done, SendMessage m0-supervisor with: commit SHA, phase list with one line each, dependency on A/B per phase,
the validation questions with your recommendations, plan path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
