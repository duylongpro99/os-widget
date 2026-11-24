# Brief: m2-menu-bar-app-p06-cook

You are session "m2-menu-bar-app-p06-cook". Your only job: implement Phase 6 of the M2 plan (sign, install on
this MacBook, acceptance script and run, docs) with `/ak-cook`, on its own branch and worktree. You do NOT merge:
a separate review session will review and merge. The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Main is at 27b582b (or later docs commits): phases 1–5 merged and marked done. `cd apps/macos/OSWidgetKit &&
  swift test` → 122 tests in 12 suites pass (1 live test skipped). `cargo test --workspace` passes.
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md (Preconditions, "Nhánh theo kết quả thử nghiệm", Done
  means), phase-06-nghiem-thu-va-tai-lieu.md, the "Ghi chú" of phases 1–5, scripts/acceptance-server.sh (pattern),
  plans/reports/review-261123-m2-p0{1..5}.md, plans/261123-2105-m2-menu-bar-app-supervisor/follow-ups.md
  (read-only: the deferred running-app checks you must now cover), docs/architecture.md §6 §9, docs/roadmap.md.
- Operator decisions:
  - 2026-11-23 ~21:05: "Cook ngay, chưa ký/cài (Đề xuất)" (phases 1–5, done).
  - 2026-11-23 22:35 (D1), lifts the wait for experiment A: "chúng ta không thể chời tới ngày 30/11 để tiếp tục,
    để note lại đó đến ngày sẽ kiểm tra lại, cứ move on". Meaning: do Phase 6 now on the "A đạt" branch (Personal
    Team 22LZWPB3XL, store in group container 22LZWPB3XL.os-widget). The A day-8 check stays on 2026-11-30; it
    is NOT yours. Write in docs that A's day-8 result is still pending and that the branch may change then.
  - Earlier: M2 installs only on this MacBook; second device simulated by API with the client token; §10.4 needs
    another machine running only the CLI.
- Experiment A is still running and must not be disturbed: never rebuild, re-sign, reinstall, open, quit or delete
  /Applications/WidgetProbe.app or its widget, and never read, write or delete files in
  ~/Library/Group Containers/22LZWPB3XL.os-widget other than OSWidget's own `store.json` (and its temp/backup
  files). Before signing, record `security find-identity -v -p codesigning | wc -l` and the identity's SHA-1
  fingerprint count (do not print the email or hash in reports); after signing, check it is unchanged (Xcode must
  reuse the existing Apple Development certificate, never create or revoke one). If Xcode wants to revoke or
  create a certificate, stop and SendMessage m0-supervisor.
- Running in parallel: nothing else in this repo.

Work
1. `git worktree add ../os-widget-macos-acceptance -b macos-acceptance` from main; code and docs work there.
2. Write `scripts/acceptance-menu-bar.sh` exactly as the phase's Requirements say (criteria 1, 3 (3a+3b), 4, 6,
   focus, all; PASS/FAIL per criterion; trap cleanup of test items; tokens only via env and a 600 header file;
   never printed). `bash -n` and `shellcheck` clean. Commit.
3. Build and install from the worktree (same app code as main): `xcodegen generate`, Release build with
   `-allowProvisioningUpdates` signed with the project's team, derived data outside the repo. Check
   `codesign -d --entitlements - ` shows app-sandbox, network.client, application-groups 22LZWPB3XL.os-widget;
   `codesign --verify --deep --strict` passes. Copy to /Applications/OSWidget.app (replace only OSWidget.app),
   then `open` it. Check: process runs, no Dock icon (LSUIElement / `lsappinfo info` shows UIElement), menu bar
   icon exists, log subsystem local.oswidget.app shows startup lines, StoreLocation resolved to the group
   container (path only), single instance.
4. Configuration needs the operator: the Settings window wants Worker URL (https://os-widget.longdaobk17.workers.dev),
   the client token, Supabase URL (https://gykrhmpliphrcpiryzuq.supabase.co) and the publishable key. Do not type
   tokens yourself into the UI and do not fetch the publishable key via the supabase CLI (it hung once). When the
   app is installed and running, SendMessage m0-supervisor: "ready for operator config" with the exact steps, and
   keep working on docs drafts (step 7) while waiting.
5. After the supervisor says config is done: run `scripts/acceptance-server.sh` (expect 8/8), reading tokens from
   the Keychain (`security find-generic-password -s os-widget-client-token -w`, `-s os-widget-publish-token`) into
   env without echo. Then verify non-interactive running-app checks yourself: a publish shows `popup.shown` with
   latency_ms in `log show`; `realtime.state joined` and `sync.applied` appear (if no Realtime signal arrives,
   record it with the `system` message note from phase-03 Ghi chú); lsof shows one WebSocket; deleted/read test
   items reach the server. Use `source: "acceptance-m2"`, ttl 3600, clean up.
6. Interactive acceptance: the script needs the operator (y/n answers, TextEdit focus, Wi-Fi off, another machine
   for CLI publish, logout/login, overnight sleep). Prepare one copy-paste command for the operator that loads the
   tokens from the Keychain into env without echo and runs `scripts/acceptance-menu-bar.sh all 2>&1 | tee
   <scratch file>`, plus a short Vietnamese checklist for the manual items in follow-ups.md (link click in a card,
   right-click menu checkmarks, light/dark, popup 30 s and hover pause, "+N" opens the list, full-screen, panel
   size with image, logout/login autostart, sleep/wake). SendMessage m0-supervisor with both and wait for the
   results relayed back. Do not wait on an interactive prompt yourself.
7. Write plans/261123-1547-m2-menu-bar-app/reports/acceptance.md (sanitized output, operator answers, macOS,
   Xcode, commit, clock skew from `sntp time.apple.com`), docs/architecture.md §6 and §9, docs/roadmap.md
   Giai đoạn 2 "Kết quả" as the phase says, with A day-8 marked pending (2026-11-30). Do not edit b-results.md,
   a-c-results.md or the A/B rows of the roadmap.
8. Commit on the branch; leave worktree and branch for review. Do not mark phase 6 or the plan done (review does).

Checks
- `bash -n scripts/acceptance-menu-bar.sh` and `shellcheck scripts/acceptance-menu-bar.sh` clean.
- swift test and `cargo test --workspace` pass in the worktree.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|sb_publishable_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'`
  empty; no token, key, email or certificate hash in any committed file or message.
- acceptance.md has PASS/FAIL for 1, 3, 4, 6, focus, with latency_ms for 1, or states exactly which items the
  operator has not run yet.
- WidgetProbe untouched: its bundle mtime and `codesign -dv` identifier unchanged before/after (record both).

Rules
- Write scope: the worktree ../os-widget-macos-acceptance (scripts/, docs/, plans/261123-1547-m2-menu-bar-app/
  reports/), /Applications/OSWidget.app, OSWidget's Keychain/Login Items entries via the app only, your report.
- Live server: only test items with source "acceptance-m2" and ttl 3600; PATCH/DELETE only those items. No
  Cloudflare/Supabase admin, no GitHub, no push.
- Never print raw tokens, keys, JWTs or certificate hashes; report only success/failure and counts.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No plan/phase/milestone IDs in code, comments, script names, commit messages. `git add` explicit paths only.
- Stop every process you start (log stream, tail, etc.); leave OSWidget.app running (it is the product).
- Report: plans/reports/cook-261123-m2-p06.md in Vietnamese, committed on the branch.

When done, SendMessage m0-supervisor with: branch head SHA, commits, signing/codesign results, identity count
unchanged, WidgetProbe untouched evidence, acceptance results per criterion (latency_ms), items still pending the
operator, docs changed, report path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
