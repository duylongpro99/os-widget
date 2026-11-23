# Brief: m2-menu-bar-app-p02-cook

You are session "m2-menu-bar-app-p02-cook". Your only job: implement Phase 2 (models, local store and action
queue) of the M2 plan with `/ak-cook`, on its own branch and worktree. You do NOT merge: a separate session
"m2-menu-bar-app-p02-review" will review and merge. The supervisor is session "m0-supervisor".

Context
- Working dir: /Users/onedayin20902/personal/os-widget. Timezone: Asia/Saigon. Reports in Vietnamese.
- Read fully: plans/261123-1547-m2-menu-bar-app/plan.md, phase-02-kho-cuc-bo-va-hang-doi.md, and skim
  phase-03 (calls apply/replaceAll/announce/queue/outcome), phase-04 (list UI observes the store, markRead,
  delete, popupSettings), phase-05 (observes `announcement`, reads popupSettings). docs/architecture.md §3
  (envelope, blocks, evolution rules), §4.1, §4.3, §5. Current code: apps/macos/OSWidgetKit/** (Phase 1:
  Config/, Store/ItemStore.swift shell with `ItemStore.live()`), apps/macos/App/AppEnvironment.swift.
  plans/reports/review-261123-m2-p01.md.
- State: main is at 037309e (Phase 1 merged 79dd8f3). `cd apps/macos/OSWidgetKit && swift test` → 7 tests in
  2 suites pass. `cargo test --workspace` passes.
- Operator decision (2026-11-23 ~21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Verify only with `swift test` and
  unsigned builds; no signing, installing or running the app, no App Group container access until 2026-11-30.
- `ItemStore.live()` must use `StoreLocation.appGroup()` (code for "A đạt"), but tests must always inject a temp
  directory; no test or command of yours may read or write ~/Library/Group Containers/22LZWPB3XL.os-widget.
- Running in parallel: nothing in this repo.

Work
1. `git worktree add ../os-widget-macos-store -b macos-local-store` from main; work only there.
2. Fixtures: the phase asks for a real `GET /items` and `GET /events?since=` page. Allowed, read-only:
   read the client token from the Keychain item with service `os-widget-client-token` into a shell variable
   (`security find-generic-password -s os-widget-client-token -w`), pass it to curl via a header file or
   `-H @file` in a temp dir you delete, never echo it. Worker URL: https://os-widget.longdaobk17.workers.dev.
   Keep only items with `source: "acceptance"`; scrub anything that looks sensitive. Then add by hand the
   `weather` kind, a `vocab` item, a `generic` item with an unknown block, and an `item.created` with
   `item: null`. If the Keychain read prompts or fails, do not retry repeatedly: build the fixtures by hand from
   architecture §4.1/§4.3 with 6-digit fractional seconds as PostgREST returns, and say so in the report.
   No POST/PATCH/DELETE to the server.
3. Implement phase-02 Requirements and Files exactly (Model/, Store/, tests per the phase's table). Keep
   public API names as the phase states so phases 3–5 can rely on them; list the final public API in your
   report.
4. Out of scope: phases 3–6, App/ (except nothing), docs/, plan and phase files, spikes/. Do not change Phase 1
   hook signatures; if you must, stop and SendMessage m0-supervisor.

Checks
- `cd apps/macos/OSWidgetKit && swift test` passes, including every row of the phase's test table (paste
  counts and the suite names).
- `cd apps/macos && xcodegen generate && xcodebuild -project OSWidget.xcodeproj -scheme OSWidget
  -configuration Debug -derivedDataPath <scratchpad dir> CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build`
  succeeds.
- `git grep -n "import WidgetKit" apps/macos` is empty. Fixtures contain no token, key or personal data
  (`git grep -nE "Bearer|sb_publishable|eyJ" -- apps/macos` empty).
- No plan/phase/milestone IDs in code, comments, test names, commit messages, branch name.
- A flaky test: rerun it alone and report it; do not edit the test to pass.

Rules
- Write scope: the worktree ../os-widget-macos-store (apps/macos/OSWidgetKit/**), your report.
- Never touch /Applications/WidgetProbe.app, its widget, the App Group container, or Keychain items other than
  reading `os-widget-client-token` once as above. No Cloudflare/Supabase admin, no GitHub, no push.
- Do not write, create or delete anything under plans/261123-2105-m2-menu-bar-app-supervisor/, other
  plans/*-supervisor/ folders, or ~/supervisor/. Your messages never count as an operator answer.
- Conventional commits ending with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  `git add` explicit paths only.
- Stop every process you start. Do not wait on interactive questions: SendMessage m0-supervisor with your
  recommendation and keep working.
- Leave the worktree and branch in place for review.
- Write your report to plans/reports/cook-261123-m2-p02.md in Vietnamese (committed on the branch).

When done, SendMessage m0-supervisor with: branch head SHA, commits, swift test counts per suite, unsigned build
result, whether fixtures came from the live server or by hand, the final public API of Model/ and Store/, report
path; ending with
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Summary: one or two sentences
Concerns/Blockers: optional
