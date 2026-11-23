# Follow-ups

Carried from plans/261122-1500-m0-supervisor/follow-ups.md: probe app day-8 check due 2026-11-30 (needs operator).
- envelope: positional JSON arrays inside `body` are still accepted; Worker must keep storing `to_value(&envelope.content)` (from m1-server-p02-review, 2026-11-23)
- envelope: URL check is prefix-only, so "https://" with no host passes (from m1-server-p02-review, 2026-11-23)
- cli: unused clap `env` feature; server URL may be http://; a redirect turns POST into tokenless GET and shows a misleading 401 hint (from m1-server-p04-review, 2026-11-23)
- worker: uppercase UUID returns 404; no log when the two secrets are identical; one test uses ttl 0 (from m1-server-p03-review, 2026-11-23)
- supabase (from Phase 1 review): Supabase grants anon default privileges on new tables, so the future vocab_words and settings tables need explicit revokes in their own migration. The purge cron runs at 03:17 UTC (10:17 Asia/Saigon).
- scripts (from Phase 5 review): measure-worker.sh publishes items with no ttl and does not delete them (pre-existing); if the CLI publish succeeds and the script then fails, that item is left to expire by its ttl 3600.
- ops: the Supabase CLI lost its Keychain access after D3; the Phase 5 reviewer read the "Supabase CLI" Keychain item via `security` into SUPABASE_ACCESS_TOKEN. Operator may click "Always Allow" next time the prompt appears.
