-- Vocabulary store and the scheduled sender that turns one word into a vocab
-- item. See docs/architecture.md section 4.4.
--
-- The Worker's Cron Trigger only calls rpc/vocab_tick: every choice (is it due,
-- which word, what to do when all words were sent) lives here, so a cron run
-- costs the Worker one request and changing behaviour is a settings row, not a
-- deploy.

create table vocab_words (
  word        text primary key
              check (word = lower(btrim(word)) and word <> ''),
  entry       jsonb not null,       -- the body of a vocab item, as validated by the envelope crate
  origin      text not null,        -- book title or dictionary API name
  added_at    timestamptz not null default now(),
  sent_at     timestamptz
);

-- vocab_tick looks for unsent words on every run.
create index vocab_words_sent_at on vocab_words (sent_at);

create table settings (
  key   text primary key,
  value jsonb not null
);

-- Same two layers as items: no table privileges for client roles, and RLS on
-- with no policies. Only the service role (the Worker) reaches these tables.
revoke all on vocab_words from anon, authenticated;
revoke all on settings from anon, authenticated;
alter table vocab_words enable row level security;
alter table settings enable row level security;

-- Defaults. do nothing keeps values already edited when the migration is
-- applied again. vocab_last_sent_at is state written by vocab_tick.
insert into settings (key, value) values
  ('vocab_enabled',          'true'),
  ('vocab_interval_minutes', '60'),
  ('vocab_when_exhausted',   '"rotate"'),
  ('vocab_priority',         '"normal"'),
  ('vocab_item_ttl_seconds', '86400'),
  ('vocab_last_sent_at',     'null')
on conflict (key) do nothing;

-- Stores a batch of vocab bodies the Worker already validated. The key is the
-- trimmed, lower-cased word, so ingesting a word again never duplicates it.
-- Ingesting again replaces entry and origin and keeps added_at and sent_at, so
-- a re-ingested word is not sent again early. When the new entry has no
-- context but the stored one has, the stored context is kept: a dictionary
-- ingest after a book ingest must not lose the sentence from the book.
-- Within one batch the last occurrence of a word wins. Returns the number of
-- distinct words written.
create function vocab_upsert(p_origin text, p_words jsonb) returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  written integer;
begin
  if p_words is null or jsonb_typeof(p_words) <> 'array' then
    raise exception 'p_words must be a JSON array' using errcode = '22023';
  end if;

  insert into public.vocab_words as v (word, entry, origin)
  select distinct on (w.word) w.word, w.entry, p_origin
  from (
    select lower(btrim(e.value ->> 'word')) as word, e.value as entry, e.ord
    from jsonb_array_elements(p_words) with ordinality as e(value, ord)
  ) as w
  order by w.word, w.ord desc
  on conflict (word) do update
    set entry = case
                  when coalesce(btrim(excluded.entry ->> 'context'), '') = ''
                   and coalesce(btrim(v.entry ->> 'context'), '') <> ''
                  then excluded.entry || jsonb_build_object('context', v.entry -> 'context')
                  else excluded.entry
                end,
        origin = excluded.origin;

  get diagnostics written = row_count;
  return written;
end;
$$;

-- One cron run, in one transaction. Returns a JSON object whose status is one of:
--   disabled   vocab_enabled is false
--   not_due    the interval since the last send has not elapsed
--   empty      vocab_words has no rows
--   exhausted  every word was sent and vocab_when_exhausted is "stop"
--   duplicate  the item for this word and minute already exists (only possible
--              when a single-word table rotates twice within one minute)
--   sent       one item was created; also carries word, item_id and rotated
-- Every result carries warnings: the settings keys whose value had the wrong
-- type or range and were replaced by their default. A bad setting never makes
-- the function fail, and no item is ever created without a word.
create function vocab_tick() returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  warnings      text[] := '{}';
  cfg           jsonb;
  v             jsonb;
  enabled       boolean := true;
  interval_min  integer := 60;
  when_done     text := 'rotate';
  prio          text := 'normal';
  ttl_s         integer := 86400;
  last_sent     timestamptz;
  picked        public.vocab_words%rowtype;
  last_word     text;
  word_count    bigint;
  rotated       boolean := false;
  new_id        text;
  first_def     text;
begin
  -- Overlapping runs wait for each other instead of sending twice.
  perform pg_advisory_xact_lock(hashtext('os-widget.vocab_tick'));

  select coalesce(jsonb_object_agg(s.key, s.value), '{}')
  into cfg
  from public.settings as s
  where s.key like 'vocab\_%';

  -- A missing key silently uses its default; a present but invalid one warns.
  v := cfg -> 'vocab_enabled';
  if v is not null then
    if jsonb_typeof(v) = 'boolean' then
      enabled := v::boolean;
    else
      warnings := array_append(warnings, 'vocab_enabled');
    end if;
  end if;

  v := cfg -> 'vocab_interval_minutes';
  if v is not null then
    -- CASE guarantees the cast only runs on a JSON number.
    if (case when jsonb_typeof(v) = 'number'
            then v::numeric = trunc(v::numeric) and v::numeric between 1 and 5256000  -- at most ten years
            else false end) then
      interval_min := v::integer;
    else
      warnings := array_append(warnings, 'vocab_interval_minutes');
    end if;
  end if;

  v := cfg -> 'vocab_when_exhausted';
  if v is not null then
    if jsonb_typeof(v) = 'string' and v #>> '{}' in ('stop', 'rotate') then
      when_done := v #>> '{}';
    else
      warnings := array_append(warnings, 'vocab_when_exhausted');
    end if;
  end if;

  v := cfg -> 'vocab_priority';
  if v is not null then
    if jsonb_typeof(v) = 'string' and v #>> '{}' in ('low', 'normal', 'high') then
      prio := v #>> '{}';
    else
      warnings := array_append(warnings, 'vocab_priority');
    end if;
  end if;

  v := cfg -> 'vocab_item_ttl_seconds';
  if v is not null then
    if (case when jsonb_typeof(v) = 'number'
            then v::numeric = trunc(v::numeric) and v::numeric between 1 and 31536000  -- at most one year
            else false end) then
      ttl_s := v::integer;
    else
      warnings := array_append(warnings, 'vocab_item_ttl_seconds');
    end if;
  end if;

  v := cfg -> 'vocab_last_sent_at';
  if v is not null and jsonb_typeof(v) <> 'null' then
    begin
      if jsonb_typeof(v) <> 'string' then
        raise exception using errcode = '22007';
      end if;
      last_sent := (v #>> '{}')::timestamptz;
    exception when others then
      -- Treated as never sent, so the next run sends and rewrites it.
      last_sent := null;
      warnings := array_append(warnings, 'vocab_last_sent_at');
    end;
  end if;

  if not enabled then
    return jsonb_build_object('status', 'disabled', 'warnings', to_jsonb(warnings));
  end if;

  -- One minute of slack absorbs the jitter between cron runs, so a run that
  -- fires slightly early does not push the send a whole cron period later.
  if last_sent is not null
     and now() < last_sent + make_interval(mins => interval_min) - interval '1 minute' then
    return jsonb_build_object('status', 'not_due', 'warnings', to_jsonb(warnings));
  end if;

  -- Plain for update, not skip locked: the advisory lock already serializes
  -- runs, and skipping a row an ingest briefly locks would look like
  -- "every word was sent" and trigger a rotation by mistake.
  select * into picked
  from public.vocab_words as w
  where w.sent_at is null
  order by random()
  limit 1
  for update;

  if not found then
    select count(*) into word_count from public.vocab_words;
    if word_count = 0 then
      return jsonb_build_object('status', 'empty', 'warnings', to_jsonb(warnings));
    end if;
    if when_done = 'stop' then
      return jsonb_build_object('status', 'exhausted', 'warnings', to_jsonb(warnings));
    end if;

    -- Rotate: start over, but never resend the word that was just sent.
    select w.word into last_word
    from public.vocab_words as w
    order by w.sent_at desc nulls last, w.word
    limit 1;

    update public.vocab_words set sent_at = null where sent_at is not null;
    rotated := true;

    select * into picked
    from public.vocab_words as w
    where w.sent_at is null
      and (word_count = 1 or w.word <> last_word)
    order by random()
    limit 1
    for update;

  end if;

  first_def := picked.entry #>> '{meanings,0,definition}';

  insert into public.items (id, kind, source, priority, title, summary, body, dedupe_key, expires_at)
  values (
    gen_random_uuid()::text,
    'vocab',
    'vocab-cron',
    prio,
    picked.entry ->> 'word',
    '(' || (picked.entry ->> 'pos') || ') ' || left(first_def, 140),
    picked.entry,
    'vocab:' || picked.word || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDD"T"HH24MI'),
    now() + make_interval(secs => ttl_s)
  )
  on conflict (dedupe_key) do nothing
  returning id into new_id;

  if new_id is null then
    return jsonb_build_object('status', 'duplicate', 'word', picked.word,
                              'warnings', to_jsonb(warnings));
  end if;

  update public.vocab_words set sent_at = now() where word = picked.word;

  insert into public.settings (key, value)
  values ('vocab_last_sent_at', to_jsonb(now()))
  on conflict (key) do update set value = excluded.value;

  return jsonb_build_object(
    'status', 'sent',
    'word', picked.word,
    'item_id', new_id,
    'rotated', rotated,
    'warnings', to_jsonb(warnings)
  );
end;
$$;

-- Postgres grants execute to public by default, and PostgREST would expose
-- both functions to the anon key. Only the Worker's service role may call them.
revoke execute on function public.vocab_upsert(text, jsonb) from public, anon, authenticated;
revoke execute on function public.vocab_tick() from public, anon, authenticated;
grant execute on function public.vocab_upsert(text, jsonb) to service_role;
grant execute on function public.vocab_tick() to service_role;
