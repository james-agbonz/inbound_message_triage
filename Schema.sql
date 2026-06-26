-- inbound_messages : triage pipeline log


create table if not exists inbound_messages (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),

  -- original payload
  from_address    text,
  channel         text,
  message         text,            -- nullable: rejected/empty rows are still logged for audit

  -- AI analysis
  category        text,            -- billing | access_issue | sales_question | spam | other
  urgency         text,            -- low | medium | high
  needs_human     boolean,
  suggested_reply text,

  -- pipeline bookkeeping
  notified        boolean default false,
  status          text default 'processed',  -- processed | ai_fallback | rejected | duplicate
  error_note      text,                       -- why a row was rejected or fell back
  dedupe_hash     text                        -- sha256(from + channel + message)
);

-- Idempotency: the same (from, channel, message) can only land once.
-- Partial index so multiple NULL-hash reject rows don't collide.
create unique index if not exists inbound_messages_dedupe_uq
  on inbound_messages (dedupe_hash)
  where dedupe_hash is not null;

-- Helpful read indexes
create index if not exists inbound_messages_created_idx on inbound_messages (created_at desc);
create index if not exists inbound_messages_status_idx  on inbound_messages (status);


-- STRETCH: today's message volume by category

create or replace view v_today_volume_by_category as
select
  coalesce(category, 'unclassified') as category,
  count(*)                            as total,
  count(*) filter (where needs_human) as needs_human_count
from inbound_messages
where created_at >= date_trunc('day', now())
  and status in ('processed', 'ai_fallback')
group by 1
order by total desc;
