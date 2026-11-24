-- Tests for the vocab store: vocab_upsert, vocab_tick and their permissions.
-- Runs with `supabase test db`. Everything happens in one transaction, so
-- now() is fixed; time passing is simulated by moving vocab_last_sent_at back.

begin;
create extension if not exists pgtap with schema extensions;

select plan(69);

-- Helpers ---------------------------------------------------------------

create function pg_temp.entry(w text, ctx text default null) returns jsonb
language sql as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'word', w,
    'ipa', '/' || w || '/',
    'pos', 'noun',
    'audio_url', null,
    'meanings', jsonb_build_array(jsonb_build_object(
      'definition', 'meaning of ' || w, 'examples', jsonb_build_array('An example.'))),
    'context', ctx,
    'synonyms', '[]'::jsonb,
    'antonyms', '[]'::jsonb
  ))
$$;

-- Empties the vocab state and restores default settings.
create function pg_temp.reset_state() returns void
language sql as $$
  delete from public.events;
  delete from public.items;
  delete from public.vocab_words;
  delete from public.settings;
  insert into public.settings (key, value) values
    ('vocab_enabled', 'true'),
    ('vocab_interval_minutes', '60'),
    ('vocab_when_exhausted', '"rotate"'),
    ('vocab_priority', '"normal"'),
    ('vocab_item_ttl_seconds', '86400'),
    ('vocab_last_sent_at', 'null');
$$;

create function pg_temp.set_setting(k text, v jsonb) returns void
language sql as $$
  update public.settings set value = v where key = k;
$$;

-- Pretends the last send happened `ago` before now.
create function pg_temp.last_sent(ago interval) returns void
language sql as $$
  update public.settings set value = to_jsonb(now() - ago) where key = 'vocab_last_sent_at';
$$;

create function pg_temp.add_words(variadic ws text[]) returns void
language sql as $$
  select public.vocab_upsert('test', jsonb_agg(pg_temp.entry(w))) from unnest(ws) as w;
$$;

create temp table r (name text primary key, result jsonb);

-- Default settings --------------------------------------------------------

select is(
  (select jsonb_object_agg(key, value) from public.settings where key like 'vocab\_%'),
  '{"vocab_enabled": true, "vocab_interval_minutes": 60, "vocab_when_exhausted": "rotate",
    "vocab_priority": "normal", "vocab_item_ttl_seconds": 86400, "vocab_last_sent_at": null}'::jsonb,
  'the migration seeds the default settings'
);

-- Empty store -------------------------------------------------------------

select pg_temp.reset_state();
select is(public.vocab_tick() ->> 'status', 'empty', 'an empty store reports empty');
select is((select count(*) from public.items), 0::bigint, 'an empty store creates no item');

-- First send --------------------------------------------------------------

select pg_temp.reset_state();
select pg_temp.add_words('serendipity');
insert into r values ('first', public.vocab_tick());

select is((select result ->> 'status' from r where name = 'first'), 'sent',
  'a word never sent before is sent when nothing was sent yet');
select is((select result ->> 'word' from r where name = 'first'), 'serendipity',
  'the result names the word sent');
select is((select result -> 'rotated' from r where name = 'first'), 'false'::jsonb,
  'a first send is not a rotation');
select is((select result -> 'warnings' from r where name = 'first'), '[]'::jsonb,
  'default settings give no warning');
select is((select count(*) from public.items), 1::bigint, 'exactly one item is created');
select is(
  (select id from public.items),
  (select result ->> 'item_id' from r where name = 'first'),
  'the result carries the id of the created item'
);
select results_eq(
  $$ select kind, source, priority, title, summary from public.items $$,
  $$ values ('vocab'::text, 'vocab-cron'::text, 'normal'::text, 'serendipity'::text,
             '(noun) meaning of serendipity'::text) $$,
  'the item is a normal-priority vocab item titled by the word with a pos and definition summary'
);
select is((select body from public.items), pg_temp.entry('serendipity'),
  'the item body is the stored entry');
select is((select expires_at - created_at from public.items), interval '86400 seconds',
  'the item expires after the default ttl of one day');
select is(
  (select dedupe_key from public.items),
  'vocab:serendipity:' || to_char(now() at time zone 'UTC', 'YYYYMMDD"T"HH24MI'),
  'the dedupe key names the word and the UTC minute'
);
select results_eq(
  $$ select type, item_id from public.events $$,
  $$ select 'item.created'::text, id from public.items $$,
  'the insert records exactly one item.created event for the item'
);
select is((select sent_at from public.vocab_words where word = 'serendipity'), now(),
  'the word is marked as sent');
select is(
  (select (value #>> '{}')::timestamptz from public.settings where key = 'vocab_last_sent_at'),
  now(),
  'the time of the last send is recorded'
);

-- Interval ----------------------------------------------------------------

select pg_temp.add_words('apple', 'banana', 'cherry');
select is(public.vocab_tick() ->> 'status', 'not_due', 'calling again right away is not due');
select is((select count(*) from public.items), 1::bigint, 'a run that is not due creates no item');

select pg_temp.last_sent('30 minutes');
select is(public.vocab_tick() ->> 'status', 'not_due',
  '30 minutes after the last send with a 60 minute interval is not due');

select pg_temp.last_sent('59 minutes');
select is(public.vocab_tick() ->> 'status', 'sent',
  '59 minutes after the last send is due thanks to one minute of slack');

select pg_temp.set_setting('vocab_interval_minutes', '10');
select pg_temp.last_sent('8 minutes');
select is(public.vocab_tick() ->> 'status', 'not_due',
  'with the interval changed to 10 minutes, 8 minutes is not due');
select pg_temp.last_sent('10 minutes');
select is(public.vocab_tick() ->> 'status', 'sent',
  'with the interval changed to 10 minutes, 10 minutes is due without a redeploy');

-- Exhausted, stop ---------------------------------------------------------

select pg_temp.reset_state();
select pg_temp.add_words('apple', 'banana');
update public.vocab_words set sent_at = now() - interval '2 hours';
select pg_temp.set_setting('vocab_when_exhausted', '"stop"');
select pg_temp.last_sent('2 hours');
select is(public.vocab_tick() ->> 'status', 'exhausted', 'all words sent with stop reports exhausted');
select is((select count(*) from public.items), 0::bigint, 'an exhausted stop creates no item');
select is((select count(*) from public.vocab_words where sent_at is null), 0::bigint,
  'stop leaves every word marked as sent');

-- Exhausted, rotate -------------------------------------------------------

-- Repeated because the pick is random: the word sent last must never be the
-- first word of the new round.
create function pg_temp.rotate_once() returns jsonb
language plpgsql as $$
begin
  perform pg_temp.reset_state();
  perform pg_temp.add_words('apple', 'banana', 'cherry');
  update public.vocab_words set sent_at = now() - interval '3 hours' where word = 'apple';
  update public.vocab_words set sent_at = now() - interval '2 hours' where word = 'banana';
  update public.vocab_words set sent_at = now() - interval '1 hour'  where word = 'cherry';
  perform pg_temp.last_sent('1 hour');
  return public.vocab_tick();
end;
$$;

create temp table rotations as
  select i, pg_temp.rotate_once() as result from generate_series(1, 30) as i;

select is(
  (select count(*) from rotations where result ->> 'status' = 'sent' and result -> 'rotated' = 'true'),
  30::bigint,
  'all words sent with rotate starts a new round and reports rotated'
);
select is(
  (select count(*) from rotations where result ->> 'word' = 'cherry'),
  0::bigint,
  'a rotation never resends the word sent last'
);
select is(
  (select count(*) from public.vocab_words where sent_at is null), 2::bigint,
  'after a rotation only the word just sent is marked as sent'
);
select is((select count(*) from public.items), 1::bigint, 'a rotation creates exactly one item');

-- A single word rotates onto itself; a second rotation in the same minute
-- would repeat its dedupe key, so it is reported instead of failing.
select pg_temp.reset_state();
select pg_temp.add_words('solo');
update public.vocab_words set sent_at = now() - interval '2 hours';
select pg_temp.last_sent('2 hours');
select is(public.vocab_tick() ->> 'word', 'solo', 'a single word rotates onto itself');
select pg_temp.last_sent('2 hours');
select is(public.vocab_tick() ->> 'status', 'duplicate',
  'the same word twice in one minute reports duplicate instead of failing');
select is((select count(*) from public.items), 1::bigint, 'a duplicate creates no second item');

-- Disabled ----------------------------------------------------------------

select pg_temp.reset_state();
select pg_temp.add_words('apple');
select pg_temp.set_setting('vocab_enabled', 'false');
select is(public.vocab_tick() ->> 'status', 'disabled', 'vocab_enabled false reports disabled');
select is((select count(*) from public.items), 0::bigint, 'disabled creates no item');
select is((select sent_at from public.vocab_words), null::timestamptz,
  'disabled leaves the word unsent');

-- Invalid settings --------------------------------------------------------

select pg_temp.reset_state();
select pg_temp.add_words('apple', 'banana');
select pg_temp.set_setting('vocab_interval_minutes', '0');
select pg_temp.last_sent('30 minutes');
insert into r values ('interval0', public.vocab_tick());
select is((select result ->> 'status' from r where name = 'interval0'), 'not_due',
  'an interval of 0 falls back to 60 minutes');
select is((select result -> 'warnings' from r where name = 'interval0'),
  '["vocab_interval_minutes"]'::jsonb, 'an interval of 0 is reported as a warning');
select pg_temp.last_sent('59 minutes');
select is(public.vocab_tick() ->> 'status', 'sent',
  'with the fallback of 60 minutes, 59 minutes is due');

select pg_temp.reset_state();
select pg_temp.add_words('apple');
select pg_temp.set_setting('vocab_priority', '"urgent"');
select pg_temp.set_setting('vocab_item_ttl_seconds', '"a day"');
select pg_temp.set_setting('vocab_enabled', '"yes"');
select pg_temp.set_setting('vocab_last_sent_at', '"not a time"');
insert into r values ('badsettings', public.vocab_tick());
select is((select result ->> 'status' from r where name = 'badsettings'), 'sent',
  'invalid settings never make the run fail');
select is((select result -> 'warnings' from r where name = 'badsettings'),
  '["vocab_enabled", "vocab_priority", "vocab_item_ttl_seconds", "vocab_last_sent_at"]'::jsonb,
  'every invalid setting is named in warnings');
select is((select priority from public.items), 'normal', 'an unknown priority falls back to normal');
select is((select expires_at - created_at from public.items), interval '86400 seconds',
  'a ttl that is not a number falls back to one day');

select pg_temp.reset_state();
select pg_temp.add_words('apple', 'banana');
update public.vocab_words set sent_at = now() - interval '2 hours';
select pg_temp.set_setting('vocab_when_exhausted', '"later"');
select is(public.vocab_tick() -> 'rotated', 'true'::jsonb,
  'an unknown exhaustion mode falls back to rotate');

select pg_temp.reset_state();
select pg_temp.add_words('apple');
select pg_temp.set_setting('vocab_priority', '"high"');
select pg_temp.set_setting('vocab_item_ttl_seconds', '600');
select public.vocab_tick();
select results_eq(
  $$ select priority, expires_at - created_at from public.items $$,
  $$ values ('high'::text, interval '600 seconds') $$,
  'priority and ttl come from settings'
);

-- vocab_upsert ------------------------------------------------------------

select pg_temp.reset_state();
select is(
  public.vocab_upsert('Pride and Prejudice', jsonb_build_array(pg_temp.entry('Civil', 'He was civil to her.'))),
  1, 'upsert returns the number of words written'
);
select is((select word from public.vocab_words), 'civil', 'the key is the lower-cased word');
update public.vocab_words
  set added_at = '2026-01-01T00:00:00Z', sent_at = '2026-01-02T00:00:00Z';

select is(
  public.vocab_upsert('dictionaryapi.dev',
    jsonb_build_array(pg_temp.entry('civil') || '{"ipa": "/ˈsɪv.əl/"}')),
  1, 'upserting the same word again writes one word'
);
select is((select count(*) from public.vocab_words), 1::bigint, 'upserting a word again keeps one row');
select is((select entry ->> 'ipa' from public.vocab_words), '/ˈsɪv.əl/', 'the new entry replaces the old one');
select is((select origin from public.vocab_words), 'dictionaryapi.dev', 'the new origin replaces the old one');
select is((select entry ->> 'context' from public.vocab_words), 'He was civil to her.',
  'a new entry without context keeps the stored context');
select is((select added_at from public.vocab_words), '2026-01-01T00:00:00Z'::timestamptz,
  'upserting again keeps added_at');
select is((select sent_at from public.vocab_words), '2026-01-02T00:00:00Z'::timestamptz,
  'upserting again keeps sent_at');

select public.vocab_upsert('test', jsonb_build_array(pg_temp.entry('civil', '   ')));
select is((select entry ->> 'context' from public.vocab_words), 'He was civil to her.',
  'a blank new context also keeps the stored context');
select public.vocab_upsert('test', jsonb_build_array(pg_temp.entry('civil', 'A civil war.')));
select is((select entry ->> 'context' from public.vocab_words), 'A civil war.',
  'a new non-blank context replaces the stored one');

select is(
  public.vocab_upsert('test', jsonb_build_array(
    pg_temp.entry('Moot', 'first'), pg_temp.entry(' moot ', 'second'), pg_temp.entry('quay'))),
  2, 'a word repeated within one batch counts once'
);
select is((select entry ->> 'context' from public.vocab_words where word = 'moot'), 'second',
  'within one batch the last occurrence of a word wins');

select throws_ok(
  $$ select public.vocab_upsert('test', '{"word": "x"}') $$,
  '22023', 'p_words must be a JSON array',
  'upsert rejects a body that is not an array'
);
select throws_ok(
  $$ insert into public.vocab_words (word, entry, origin) values ('Mixed', '{}', 'test') $$,
  '23514', null,
  'a stored word must already be trimmed and lower-cased'
);

-- Permissions -------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.vocab_tick()', 'execute')
  and not has_function_privilege('authenticated', 'public.vocab_tick()', 'execute'),
  'anon and authenticated cannot execute vocab_tick'
);
select ok(
  not has_function_privilege('anon', 'public.vocab_upsert(text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.vocab_upsert(text, jsonb)', 'execute'),
  'anon and authenticated cannot execute vocab_upsert'
);
select ok(
  not has_table_privilege('anon', 'public.vocab_words', 'select, insert, update, delete')
  and not has_table_privilege('authenticated', 'public.vocab_words', 'select, insert, update, delete'),
  'anon and authenticated have no privilege on vocab_words'
);
select ok(
  not has_table_privilege('anon', 'public.settings', 'select, insert, update, delete')
  and not has_table_privilege('authenticated', 'public.settings', 'select, insert, update, delete'),
  'anon and authenticated have no privilege on settings'
);
select ok(
  has_function_privilege('service_role', 'public.vocab_tick()', 'execute')
  and has_function_privilege('service_role', 'public.vocab_upsert(text, jsonb)', 'execute'),
  'the service role can execute both functions'
);

set local role anon;
select throws_ok($$ select public.vocab_tick() $$, '42501', null, 'anon is refused vocab_tick');
select throws_ok($$ select public.vocab_upsert('x', '[]') $$, '42501', null, 'anon is refused vocab_upsert');
select throws_ok($$ select count(*) from public.vocab_words $$, '42501', null, 'anon cannot read vocab_words');
select throws_ok($$ select count(*) from public.settings $$, '42501', null, 'anon cannot read settings');
reset role;

-- Called the way the Worker calls it: as the service role through PostgREST.
select pg_temp.reset_state();
select pg_temp.add_words('apple');
set local role service_role;
select is(public.vocab_tick() ->> 'status', 'sent', 'the service role can run a whole tick');
reset role;

select * from finish();
rollback;
