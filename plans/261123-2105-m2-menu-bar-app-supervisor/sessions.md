# Sessions — M2 menu bar app supervisor (session name: m0-supervisor)

Plan: plans/261123-1547-m2-menu-bar-app/plan.md (committed ea79690, decisions d392603)
Baseline: main 29dd016; no Swift code yet (`apps/` does not exist). Rust: `cargo test --workspace` unchanged.

Operator decision (2026-11-23 ~21:05, AskUserQuestion): "Cook ngay, chưa ký/cài (Đề xuất)".
Scope of that decision: phases 1–5 are coded now and verified only with `swift test` and unsigned builds
(`CODE_SIGNING_ALLOWED=NO`). No Apple-account signing, no `-allowProvisioningUpdates`, no install to
/Applications, no running the app, no access to the App Group container 22LZWPB3XL.os-widget, never touch
WidgetProbe, until experiment A's day-8 check on 2026-11-30. After that: settle signing per the A branch, then
phase 6 (install, acceptance). If A fails, only the signing config and StoreLocation change.

Order: p01 → p02 → (p03, p04, p05 in parallel per file-ownership table) → [A day 8, 2026-11-30] → p06.

| Name | Kind | Pane / PID | Skill | Brief | Status | Result commit |
|---|---|---|---|---|---|---|
| pending-watch | process | PID 27008 | — | — | running | — |
| m2-menu-bar-app-p01-cook | session | wC:pJ3 | /ak-cook | briefs/m2-menu-bar-app-p01-cook.md | done_with_concerns, verified, stopped 21:13 | branch macos-app-project 57cc98c |
| m2-menu-bar-app-p01-review | session | wC:pJ4 | /ak-code-review | briefs/m2-menu-bar-app-p01-review.md | done, verified, stopped 21:3x | merge 79dd8f3 (fixes 15e0216 2a970a7 2d47b04 311b672), status 037309e |
| m2-menu-bar-app-p02-cook | session | wC:pJ5 | /ak-cook | briefs/m2-menu-bar-app-p02-cook.md | done, verified, stopped 21:27 | branch macos-local-store 7c56a6b |
| m2-menu-bar-app-p02-review | session | wC:pJ6 | /ak-code-review | briefs/m2-menu-bar-app-p02-review.md | done, verified, stopped 21:4x | merge 58f043e (fix dc99dda), status 3db956b |
| m2-menu-bar-app-p03-cook | session | wC:pJ7 | /ak-cook | briefs/m2-menu-bar-app-p03-cook.md | done_with_concerns, verified (81 tests), stopped | branch macos-sync-engine 877e0f9 |
| m2-menu-bar-app-p04-cook | session | wC:pJ8 | /ak-cook | briefs/m2-menu-bar-app-p04-cook.md | done_with_concerns, verified (56 tests), stopped | branch macos-menu-bar-list c989b27 |
| m2-menu-bar-app-p05-cook | session | wC:pJ9 | /ak-cook | briefs/m2-menu-bar-app-p05-cook.md | done, verified (61 tests), stopped; review waits for p04 merge | branch macos-popup-panel 05d2898 |
| m2-menu-bar-app-p04-review | session | wC:pJA | /ak-code-review | briefs/m2-menu-bar-app-p04-review.md | done, verified (59 tests), stopped | merge d8c6733 (fixes 16913d2 c8f3606), status 47c2af8 |
| m2-menu-bar-app-p05-review | session | wC:pJB | /ak-code-review | briefs/m2-menu-bar-app-p05-review.md | done, verified (78 tests), stopped | merge 037e9eb (integration 94bf789), status b25df53 |
| m2-menu-bar-app-p03-review | session | wC:pJC | /ak-code-review | briefs/m2-menu-bar-app-p03-review.md | done, verified (122 tests), stopped | merge cb824ee (fix c289e4f), status a698cf6 |
