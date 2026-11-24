# Brief: m2-menu-bar-app-p06-review

You are session "m2-menu-bar-app-p06-review". Your only job: review branch `macos-acceptance` (Phase 6 of the
M2 plan: install, acceptance script, acceptance results, docs) with `/ak-code-review`, fix the item-list finding
below on the branch, rebuild and reinstall OSWidget, get the operator's re-check through the supervisor, merge
`--no-ff` into main locally, and record the phase status. The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Branch `macos-acceptance`, head cef292c, worktree ../os-widget-macos-acceptance, based on main 27b582b.
  Commits: 78f1f09 (acceptance script), 804e582 (Edit menu so Settings fields paste), d3d7d6f (script reports a
  suppressed popup), 390ca77 and cef292c (acceptance.md, architecture §6 §9, roadmap Giai đoạn 2, cook report
  plans/reports/cook-261123-m2-p06.md).
- Main is 27b582b plus supervisor docs commits only (no code change since the branch point).
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md (Done means), phase-06-nghiem-thu-va-tai-lieu.md, the
  cook report, plans/261123-1547-m2-menu-bar-app/reports/acceptance.md, apps/macos/App/MenuBar/MenuBarController.swift.
- Supervisor already verified: 5 commits on the branch; the secret `git grep` is empty; commit messages hold no
  email other than the Co-Authored-By line; `bash -n` and shellcheck clean; WidgetProbe mtime 1795358837 and
  Identifier local.oswidget.probe unchanged.
- Results so far: server acceptance 8/8 (2026-11-24 08:40); criteria 1 (latency_ms 781), 3a, 3b, 6, focus
  (09:09 re-run) PASS; criterion 4 deferred.
- Operator statements (verbatim, with time):
  - 2026-11-23 22:35 (D1): "chúng ta không thể chời tới ngày 30/11 để tiếp tục, để note lại đó đến ngày sẽ kiểm tra
    lại, cứ move on" (do Phase 6 now on the "A đạt" branch; A day-8 check stays 2026-11-30).
  - 2026-11-23: "Bước 0 ý 2: note lại để sau nhé, hiện tại tôi chỉ có macbook ở đây" (criterion 4 / PRD §10.4
    deferred: no second machine).
  - 2026-11-24 ~09:05: "tôi làm xong rồi, chỉ có bước này báo fail" (only focus failed in the first run).
  - 2026-11-24 09:1x (D4): "không" (the item list did NOT close when they clicked into TextEdit).
  - 2026-11-24 09:3x: "gõ vẫn bình thường, checklist 1–9 đều đạt" (typing stayed in TextEdit; checklist 1–9 all pass).
- Items 10 (logout/login autostart) and 11 (overnight sleep) are pending the operator; they do not block merge.
- Running in parallel: nothing else in this repo.

Finding to fix (supervisor decision: fix in this review)
- The item list popover does not close when the user clicks another app. Impact: `isListOpen` stays true, so
  every popup is suppressed with `list_open` until the user closes the list by hand.
- Code: MenuBarController sets `popover.behavior = .transient` and calls `NSApp.activate()` in showList(); nothing
  else closes it. Cook's suspected cause (unproven): cooperative activation on macOS 14+ means the LSUIElement app
  may not become active, so no outside click or deactivation reaches the popover.
- First prove or disprove the cause cheaply (e.g. log `NSApp.isActive` after showList() via the app's Logger,
  without printing anything sensitive). Then fix with the smallest robust change, e.g. close the popover on
  `NSApplication.didResignActiveNotification` and on an `NSEvent.addGlobalMonitorForEvents(matching:
  [.leftMouseDown, .rightMouseDown])` monitor while the list is shown (remove the monitor on close). Keep the
  status-icon click toggle working (clicking the icon while open closes and does not reopen). Unit-test any
  logic you can extract; the UI behavior is checked by hand.

Work
1. Review main..macos-acceptance with `/ak-code-review`: the acceptance script (token handling via env and a 600
   header file, never printed; trap cleanup; only `source: "acceptance-m2"` items touched), EditMenu.swift, and
   docs accuracy (acceptance.md, architecture §6 §9, roadmap Giai đoạn 2) against the results above. The
   "+N keeps growing and counts deleted items" observation (PopupPolicy.merge): fix only if small and testable,
   otherwise note it in the report as a follow-up.
2. Fix the item-list finding on the branch (own commit, `fix(macos): ...`).
3. Rebuild and reinstall exactly as the cook did: `xcodegen generate`, Release build with
   `-allowProvisioningUpdates`, derived data outside the repo; `codesign --verify --deep --strict`; entitlements
   unchanged; record `security find-identity -v -p codesigning | wc -l` before and after (unchanged; if Xcode
   wants to create or revoke a certificate, stop and SendMessage m0-supervisor). Quit only OSWidget
   (`osascript -e 'quit app "OSWidget"'` or by its pid), replace only /Applications/OSWidget.app, `open` it,
   check it runs as a single UIElement instance with sync joined in the log.
4. SendMessage m0-supervisor: "ready for operator re-check" with a 3-line Vietnamese check (open the list, click
   into TextEdit: list closes; click the icon twice: opens then closes; publish while the list is closed: popup
   shows) plus one copy-paste command that publishes one test item (`source: "acceptance-m2"`, ttl 3600, token
   from the Keychain via env, no echo). Do not wait on the operator interactively; keep working on step 5.
5. Update acceptance.md with the fix and (after the supervisor relays it) the operator's re-check answer, quoted.
6. Re-run Checks, then in the main checkout: `git merge --no-ff macos-acceptance`.
7. On main: phase-06 frontmatter `status: completed`, a short "Ghi chú" (operator statements above; criterion 4
   deferred and why; items 10 and 11 pending the operator; A day-8 check on 2026-11-30 may change the signing
   branch; the item-list fix). plan.md Phases table row 6 → "Done (tiêu chí 4 hoãn: chưa có máy thứ hai)". Plan
   frontmatter `status`: set to `in-progress` (not completed), because Done means item 3 (PRD §10.4) is not met.
   Commit `docs: mark menu bar app acceptance phase done` together with your report.
8. Remove the worktree ../os-widget-macos-acceptance and delete branch macos-acceptance. Leave OSWidget running.

Checks
- On main after merge: `cd apps/macos/OSWidgetKit && swift test` passes (paste counts; 122+ in 12+ suites);
  `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration
  Debug -derivedDataPath <scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build` succeeds;
  `cargo test --workspace` passes; `bash -n` and `shellcheck scripts/acceptance-menu-bar.sh` clean.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|sb_publishable_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'`
  empty; no token, key, email or certificate hash in any committed file or message.
- WidgetProbe untouched: bundle mtime and `codesign -dv` Identifier unchanged before/after (record both).
- `git status` clean apart from pre-existing untracked files.
- No plan/phase/milestone IDs in code, comments, test names, commit messages.

Rules
- Write scope: the worktree ../os-widget-macos-acceptance, the merge on main, phase-06 file, plan.md row 6 and its
  frontmatter status, /Applications/OSWidget.app, your report.
- Experiment A must not be disturbed: never rebuild, re-sign, reinstall, open, quit or delete
  /Applications/WidgetProbe.app or its widget; never read, write or delete files in
  ~/Library/Group Containers/22LZWPB3XL.os-widget other than OSWidget's own `store.json` (and its temp/backup files).
- Live server: only test items with source "acceptance-m2" and ttl 3600; PATCH/DELETE only those. No
  Cloudflare/Supabase admin, no GitHub, no push.
- Never print raw tokens, keys, JWTs or certificate hashes; report only success/failure and counts.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  `git add` explicit paths only.
- Stop every process you start (log stream etc.); leave OSWidget.app running. Do not wait on interactive
  questions: SendMessage m0-supervisor with your recommendation and keep working on anything not blocked.
- Report: plans/reports/review-261124-m2-p06.md in Vietnamese.

When done, SendMessage m0-supervisor with: findings and handling (commit SHAs), the item-list cause (proven or
not) and fix SHA, signing/identity count/WidgetProbe evidence, operator re-check result, merge SHA, status commit
SHA, swift test counts and build result on main, worktree/branch removed; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
