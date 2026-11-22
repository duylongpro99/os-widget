-- Items published by senders, and the ordered event log that clients sync from.
-- Columns follow docs/architecture.md section 4.3 exactly.

create table items (
  id          text primary key,
  kind        text not null,
  source      text not null,
  priority    text not null default 'normal',
  title       text not null,
  summary     text not null,
  url         text,
  body        jsonb,
  dedupe_key  text unique,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz,
  read_at     timestamptz,
  deleted_at  timestamptz
);

create table events (
  seq        bigint generated always as identity primary key,
  type       text not null,        -- item.created | item.read | item.unread | item.deleted
  item_id    text not null,
  created_at timestamptz not null default now()
);

-- Writes one event per change in the same transaction as the item change,
-- so the event log never drifts from the data.
create function record_item_event() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.events (type, item_id) values ('item.created', new.id);
    return new;
  end if;

  if old.read_at is null and new.read_at is not null then
    insert into public.events (type, item_id) values ('item.read', new.id);
  elsif old.read_at is not null and new.read_at is null then
    insert into public.events (type, item_id) values ('item.unread', new.id);
  end if;

  if old.deleted_at is null and new.deleted_at is not null then
    insert into public.events (type, item_id) values ('item.deleted', new.id);
  end if;

  return new;
end;
$$;

create trigger items_record_event
  after insert or update on items
  for each row execute function record_item_event();

-- RLS on with no policies: only the service role can read or write for now.
alter table items enable row level security;
alter table events enable row level security;
