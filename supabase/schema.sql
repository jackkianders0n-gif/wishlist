-- Wishlist — Supabase schema
-- Runs in the gym tracker's Supabase project (SQL Editor → New query → paste → Run).
-- Same pattern as House Hunt: members-only tables, guarded by wl_is_member().
-- Safe to re-run: everything uses "if not exists" / "or replace".

create extension if not exists pgcrypto;

-- ---------- Members ----------

create table if not exists public.wl_members (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at   timestamptz not null default now()
);
alter table public.wl_members enable row level security;

create or replace function public.wl_is_member()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.wl_members where user_id = auth.uid());
$$;

create or replace function public.wl_member_names()
returns table (user_id uuid, display_name text)
language sql stable security definer
set search_path = public
as $$
  select m.user_id, m.display_name from public.wl_members m where public.wl_is_member();
$$;

revoke all on function public.wl_is_member() from public, anon;
revoke all on function public.wl_member_names() from public, anon;
grant execute on function public.wl_is_member() to authenticated;
grant execute on function public.wl_member_names() to authenticated;

drop policy if exists "members only" on public.wl_members;
create policy "members only" on public.wl_members
  for select to authenticated using (public.wl_is_member());

-- ---------- Items (one row per thing you want) ----------

create table if not exists public.wl_items (
  id             uuid primary key default gen_random_uuid(),
  list           text not null check (list in ('flat', 'xmas')),
  category       text not null default 'Other',
  title          text not null check (length(title) between 1 and 200),
  qty            int  not null default 1 check (qty between 1 and 99),
  top_option_id  uuid,
  bought_by      uuid references public.wl_members(user_id) on delete set null,
  bought_at      timestamptz,
  promised_by_name   text check (promised_by_name is null or length(promised_by_name) between 1 and 60),  -- "Someone's getting this" (name optional)
  promised_at        timestamptz,
  promised_marked_by uuid references public.wl_members(user_id) on delete set null,
  sort           int  not null default 0,
  created_by     uuid default auth.uid(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ---------- Options (one row per product link for an item) ----------

create table if not exists public.wl_options (
  id               uuid primary key default gen_random_uuid(),
  item_id          uuid not null references public.wl_items(id) on delete cascade,
  url              text not null check (url ~* '^https?://'),
  store            text,
  title            text,
  image            text check (image is null or image ~* '^https?://'),
  price            numeric(10,2),
  previous_price   numeric(10,2),
  currency         text not null default 'GBP',
  price_checked_at timestamptz,
  auto_fetch       boolean not null default true,  -- false for shops that block us (Argos)
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists wl_options_item_idx on public.wl_options(item_id);

do $$ begin
  alter table public.wl_items
    add constraint wl_items_top_option_fk foreign key (top_option_id)
    references public.wl_options(id) on delete set null;
exception when duplicate_object then null; end $$;

-- updated_at
create or replace function public.wl_touch() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists wl_items_touch on public.wl_items;
create trigger wl_items_touch before update on public.wl_items for each row execute function public.wl_touch();
drop trigger if exists wl_options_touch on public.wl_options;
create trigger wl_options_touch before update on public.wl_options for each row execute function public.wl_touch();

-- ---------- Row-level security ----------

alter table public.wl_items   enable row level security;
alter table public.wl_options enable row level security;

drop policy if exists "members only" on public.wl_items;
create policy "members only" on public.wl_items
  for all to authenticated using (public.wl_is_member()) with check (public.wl_is_member());

drop policy if exists "members only" on public.wl_options;
create policy "members only" on public.wl_options
  for all to authenticated using (public.wl_is_member()) with check (public.wl_is_member());

-- ---------- Live updates (see each other's changes straight away) ----------

do $$ begin
  alter publication supabase_realtime add table public.wl_items;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.wl_options;
exception when duplicate_object then null; end $$;


-- =====================================================================
-- ADD THE TWO OF YOU  (run once)
-- Easiest: copy the members you already have in House Hunt:
--
--   insert into public.wl_members (user_id, display_name)
--   select user_id, display_name from public.hh_members
--   on conflict (user_id) do nothing;
--
-- Or by email (placeholders on purpose — put your real gym tracker emails in):
--
--   insert into public.wl_members (user_id, display_name)
--   select id, 'Jack'  from auth.users where email = 'jack@example.com'
--   union all
--   select id, 'Jakey' from auth.users where email = 'jakey@example.com'
--   on conflict (user_id) do nothing;
-- =====================================================================
