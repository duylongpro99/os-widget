# Follow-ups

- plan context: phase-01 claims xcodebuild present; actually only Command Line Tools installed (from m0-supervisor, 2026-11-22)
- size threshold: Cloudflare docs (2026-11-22) list no compressed limit, only 64 MiB uncompressed; Phase 5 uses the limits.md number per the plan's own risk rule, still records gzip size (from m0-p01-02-cook, 2026-11-22)
- cron min interval: docs do not state it as a limit; 1 minute inferred from cron syntax (from m0-p01-02-cook, 2026-11-22)
- postgresql@17 installed via brew (keg-only) for local migration checks (from m0-p01-02-cook, 2026-11-22)
- session reports: plans/reports/*m0* are untracked; the docs phase session commits them with its docs change (from m0-p02-review, 2026-11-22)
- supabase link: main worktree is not linked (link state lived in the removed worktree); any later `--linked` command first runs `supabase link --project-ref gykrhmpliphrcpiryzuq` (from m0-p02-review, 2026-11-22)
- worker token check: consider constant-time comparison when real publish/client tokens replace SPIKE_TOKEN (from m0-supervisor, 2026-11-22)

- D6 (2026-11-22): operator chose "keep Rust" although Rust failed the agreed p99 ≤ 5 ms threshold (POST p99 11 ms, GET p99 7 ms). Cold-start CPU of 16–21 ms exceeds the Free plan's 10 ms limit; it was not blocked during measurement. Phase 6 / roadmap should record this as an accepted risk, and watch for CPU-limit errors once real traffic starts.
- GET /events?since=0 with 159 events cost 15–19 ms CPU (p05 cook). Giai đoạn 1 should add a page limit to GET /events.
- Secret grep checks in later briefs must exclude .claude/ (`-- ':!.claude'`): 3 tracked skill files contain fake example JWTs.
- Probe app day-8 check due 2026-11-30: app still running, reopens, "Ghi dữ liệu" still updates the widget (no provisioning profile embedded; cert expires 2027-11-22). Needs the operator.
- PRD NFR-3 (stay within the free tier) is in tension with cold-start CPU 16–21 ms over the 10 ms limit; PRD left unchanged, needs an operator decision if Cloudflare starts blocking (from m0-p06-docs, 2026-11-22)
- PRD §8 still calls App Groups "chưa được xác nhận"; update it after the day-8 check passes (from m0-p06-docs, 2026-11-22)
- Day-8 check: press "Ghi dữ liệu" before reading the widget, since "App Group: lỗi" shows both for "no value yet" and for a real error (from m0-p06-docs, 2026-11-22)
- Real-secret grep pattern for later checks: `sb_secret_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}` with `-- ':!.claude'` (the plain pattern matches reports that quote it) (from m0-supervisor, 2026-11-22)

## Operator answers, 2026-11-23 08:53
- Probe app: "còn chạy" (still running on day 2). The day-8 check on 2026-11-30 is still needed.
- CPU: "CPU không quá quan trọng". Cold-start CPU over 10 ms is accepted; no PRD NFR-3 change. Only act if Cloudflare actually starts blocking requests.
- GET /events page limit: "tuỳ bạn đề xuất hợp lý". Proposal for the Giai đoạn 1 plan:
  - add a `limit` query parameter: default 100, maximum 100 (values above are capped);
  - keep `since=<seq>` as the cursor; events stay ordered by `seq`;
  - the client takes the last `seq` it received as the next `since` and calls again while it got a full page (100 events);
  - reason: 159 events cost 15–19 ms (about 0.1 ms per event), so a page of 100 stays near 10 ms, and a client catching up from 0 needs only a few calls.
