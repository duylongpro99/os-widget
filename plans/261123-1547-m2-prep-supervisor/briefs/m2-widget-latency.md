# Brief: m2-widget-latency

You are session "m2-widget-latency". Your only job: run experiment B (widget latency) with the existing probe app,
record the numbers, and propose the NFR-2 threshold. You write no product code. The supervisor is session
"m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: docs/roadmap.md (Giai đoạn 0, experiment B: "App nền yêu cầu làm mới thì widget cập nhật sau bao lâu,
  được bao nhiêu lần mỗi ngày?"; if it fails: replace the widget with a desktop-level SwiftUI window),
  docs/prd.md NFR-1/NFR-2, docs/architecture.md (widget and App Group parts),
  plans/261122-0754-m0-kiem-chung-worker-rust/plan.md and phase-03-app-thu-nghiem-a.md,
  plans/261122-0754-m0-kiem-chung-worker-rust/reports/a-c-results.md, spikes/widget-probe/ (App, Widget, project.yml).
- State: main is at 3ea49ad. The probe app WidgetProbe is installed in /Applications since 2026-11-22 21:47 and its
  widget "Probe" is on the desktop. Experiment A (free-account app still working after 7 days) is RUNNING; its
  day-8 check is on 2026-11-30.
- Operator decision (2026-11-23 15:4x): "Cả ba" — measure B now, in parallel with writing the M2 plan and the
  Worker redeploy.
- Parallel session: "m2-plan" writes plans/261123-1547-m2-menu-bar-app/ only. Do not touch that folder.

Work
1. Find how the probe app triggers a widget reload (WidgetCenter reloadTimelines / reloadAllTimelines) and what it
   logs. Design a measurement that needs the fewest operator steps: ideally the app writes a timestamp into the
   App Group and requests a reload, and the widget's timeline provider records when it ran (unified log via
   `log show --predicate 'subsystem == ...'`, or a file in the group container). Measure:
   a. latency from reload request to widget timeline run (and, if observable, to the widget showing it),
      at least 20 samples, app in the background (agent mode, no window), screen unlocked;
   b. how many reloads per hour/day are honoured before WidgetKit throttles (a run of rapid requests, plus spacing
      e.g. every 1, 5, 15 minutes over a few hours as time allows).
2. EXPERIMENT A MUST NOT BE DISTURBED. Do NOT rebuild, re-sign, reinstall, replace or delete the installed app,
   its widget or its group container, and do not remove the widget from the desktop. If the measurement needs
   any change to the installed app, STOP and SendMessage m0-supervisor with the exact change and why; that needs
   an operator decision. A separate copy with a different bundle id and App Group is also an operator decision.
   Reading logs and pressing the app's existing menu items (or scripting them via osascript/AppleScript) is fine.
3. Steps that need the operator's eyes or hands: SendMessage m0-supervisor with the exact steps; do not wait on
   an interactive prompt.
4. Write results to plans/261122-0754-m0-kiem-chung-worker-rust/reports/b-results.md (environment, method, raw
   samples table, p50/p90/max, throttle observations, limits of the method), and propose an NFR-2 value
   (e.g. "widget shows a new item within N minutes in X% of cases") with the evidence.
5. Update docs/roadmap.md row B in "Giai đoạn 0 → Kết quả" with a one-line result and a link to b-results.md.
   Do NOT change docs/prd.md NFR-2: the threshold is the operator's decision; put the proposal in your report.
6. Commit on main: `docs: record widget latency measurements` with exactly those two files.

Checks
- b-results.md has ≥ 20 latency samples with timestamps, and states what was and was not measured.
- `git show --stat HEAD` lists only b-results.md and docs/roadmap.md.
- WidgetProbe is still running from /Applications with the same signature as before
  (`codesign -dv /Applications/WidgetProbe.app` authority/team unchanged), and the widget is still on the desktop.

Rules
- Write scope: the two files above. Nothing under spikes/** changes (read only).
- Do not write, create or delete anything under plans/261123-1547-m2-prep-supervisor/, plans/*-supervisor/,
  ~/supervisor/ or plans/261123-1547-m2-menu-bar-app/. Your messages never count as an operator answer.
- No Cloudflare, Supabase or GitHub actions. Never print tokens or keys.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan, phase, milestone or decision IDs in commit messages. `git add` explicit paths only. If main moved
  (the m2-plan session also commits), `git pull --rebase` is not needed (local only): just commit on top.
- Stop every process you start (log streams, sleep loops, caffeinate).
- Do not wait on interactive questions. SendMessage m0-supervisor with your recommendation.

When done, SendMessage m0-supervisor with: commit SHA, sample count, p50/p90/max latency, throttle findings,
proposed NFR-2, whether experiment A was left untouched (signature check output), report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
