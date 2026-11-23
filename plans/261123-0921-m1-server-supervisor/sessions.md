# Sessions — M1 server supervisor (session name: m0-supervisor)

Plan: plans/261123-0159-m1-server/plan.md (committed 3bf4580)
Baseline: main 3bf4580; `cargo test --workspace` → envelope 7 passed, worker 0.

| Name | Kind | Pane / PID | Skill | Brief | Status | Result commit |
|---|---|---|---|---|---|---|
| pending-watch | process | PID 89598 | — | — | closed 13:33 | — |
| m1-server-p01-cook | session | wC:pHK | /ak-cook | briefs/m1-server-p01-cook.md | done, stopped (pushed; remote migration list verified 11:40) | b9aa56d |
| m1-server-p02-cook | session | wC:pHM | /ak-cook | briefs/m1-server-p02-cook.md | done, verified, stopped 09:31 | branch envelope-three-kinds ce6f09c |
| m1-server-p02-review | session | wC:pHN | /ak-code-review | briefs/m1-server-p02-review.md | done, verified, stopped 09:40 | merge ebe562f, fixes 017bb1a d195761, status 280c55e |
| m1-server-p03-cook | session | wC:pHQ | /ak-cook | briefs/m1-server-p03-cook.md | done, verified, stopped 09:58 | branch worker-api-two-tokens 7e961f3 |
| m1-server-p04-cook | session | wC:pHR | /ak-cook | briefs/m1-server-p04-cook.md | done, verified, stopped 09:42 | branch cli-publish 61c8855 |
| m1-server-p04-review | session | wC:pHS | /ak-code-review | briefs/m1-server-p04-review.md | done, verified, stopped 09:58 | merge 45ff5e5, status 7523776 |
| m1-server-p03-review | session | wC:pHV | /ak-code-review | briefs/m1-server-p03-review.md | done, verified, stopped 09:47 | merge 4935b4e, status 0d7fa55 |
| m1-server-p01-review | session | wC:pHX | /ak-code-review | briefs/m1-server-p01-review.md | done, verified, stopped 11:42 | merge 63ec28e, status adf07f3 |
| m1-server-p05-cook | session | wC:pHY | /ak-cook | briefs/m1-server-p05-cook.md | done_with_concerns, verified, stopped 11:54 (deploy 040e4e09, active 29517735) | 14fef50, c824c63 |
| m1-server-p05-review | session | wC:pHZ | /ak-code-review | briefs/m1-server-p05-review.md | done_with_concerns, verified, stopped 13:30 (re-run acceptance 8/8) | fixes e6d5bb4, 068edca; merge c0fd895, status 6d27b32 |
| m1-server-key-rotation | session | wC:pH0 | /ak-devops | briefs/m1-server-key-rotation.md | done, verified, stopped 13:33 (Worker 49c28da1 on new key; old key revoked) | no commits (live ops) |
