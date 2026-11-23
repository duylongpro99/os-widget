-- Locks the anon key down to reading the event log, adds that log to Realtime,
-- and schedules a daily purge of expired, deleted and old rows.
-- See docs/architecture.md sections 4.3 and 5.

-- Access is closed on two layers. Supabase grants table privileges in the
-- public schema to anon and authenticated by default; RLS without policies
-- only hides rows. Revoking the grants means a missing or wrong policy can
-- never expose data on its own.

-- items holds the content senders publish. Only the service role (the Worker)
-- reads or writes it, so no role exposed to clients keeps any privilege.
revoke all on items from anon, authenticated;

-- events holds only seq, type and item_id, no content. The anon key embedded
-- in the app may read it so the app can receive Realtime signals. The app
-- never signs in, so authenticated gets nothing.
revoke all on events from anon, authenticated;
grant select on events to anon;
create policy "anon can read events"
  on events
  for select
  to anon
  using (true);

-- Realtime tells clients a new event exists; they then fetch it through the
-- Worker. The guard keeps the migration safe to run when the table is already
-- in the publication (for example after it was added from the dashboard).
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'events'
  ) then
    alter publication supabase_realtime add table public.events;
  end if;
end;
$$;

-- Permanently removes rows nobody needs any more:
-- 1. Expired items. Clients already hide them by expires_at, so there is no
--    grace period and no event.
-- 2. Items soft-deleted more than 30 days ago. This matches the event
--    retention, so a client that catches up within 30 days still sees the
--    item.deleted event before the item disappears. Clients offline longer
--    rely on periodic reconciliation with GET /items.
-- 3. Events older than 30 days.
-- Retention is independent of an item's ttl, which defaults to 7 days.
-- security definer lets the cron job run it regardless of the caller's
-- privileges; the empty search_path stops a caller from shadowing the tables.
create function purge_old_rows() returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.items
  where expires_at < now()
     or deleted_at < now() - interval '30 days';

  delete from public.events
  where created_at < now() - interval '30 days';
end;
$$;

-- Postgres grants execute to public by default, and PostgREST would then
-- expose rpc/purge_old_rows to the anon key. Only the owner and the cron job
-- may run it.
revoke execute on function public.purge_old_rows() from public, anon, authenticated;

-- Runs the purge once a day inside the database. pg_cron keeps this pure SQL
-- job off the Worker's CPU budget and its limited Cron Triggers.
-- cron.schedule replaces an existing job with the same name, so reapplying is
-- safe.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('os-widget-purge', '17 3 * * *', 'select public.purge_old_rows()');
