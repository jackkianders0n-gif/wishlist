-- Share links: a read-only page for family (e.g. Mum), no sign-in needed.
-- Run once in the Supabase SQL Editor, AFTER 2026-11-20-someones-getting-this.sql. Safe to re-run.
--
-- How it's protected:
--  * Each link carries a long random token (made in the app). Without it you see nothing.
--  * The page can only call the three functions below. They show one list, hide bought items
--    and items someone else is getting, and can only mark/unmark "<name>'s getting this".
--  * Turning a link off (revoked_at) stops it working straight away.

create table if not exists public.wl_shares (
  id          uuid primary key default gen_random_uuid(),
  token       text not null unique check (length(token) >= 32),
  list        text not null check (list in ('flat', 'xmas')),
  for_name    text not null check (length(for_name) between 1 and 60),
  created_by  uuid default auth.uid() references public.wl_members(user_id) on delete set null,
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz
);
alter table public.wl_shares enable row level security;
drop policy if exists "members only" on public.wl_shares;
create policy "members only" on public.wl_shares
  for all to authenticated using (public.wl_is_member()) with check (public.wl_is_member());

-- Which link (if any) a "someone's getting this" came from.
alter table public.wl_items add column if not exists promised_share_id uuid
  references public.wl_shares(id) on delete set null;

-- What the share page shows.
create or replace function public.wl_share_view(p_token text)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare s public.wl_shares;
begin
  select * into s from public.wl_shares where token = p_token and revoked_at is null;
  if not found then return null; end if;
  return jsonb_build_object(
    'for_name', s.for_name,
    'list', s.list,
    'owners', (select coalesce(jsonb_agg(m.display_name order by m.display_name), '[]'::jsonb) from public.wl_members m),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'title', i.title, 'qty', i.qty, 'category', i.category,
        'mine', coalesce(i.promised_share_id = s.id, false),
        'options', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', o.id, 'title', o.title, 'store', o.store, 'url', o.url, 'image', o.image,
            'price', o.price, 'top', o.id = i.top_option_id
          ) order by (o.id = i.top_option_id) desc nulls last, o.created_at)
          from public.wl_options o where o.item_id = i.id
        ), '[]'::jsonb)
      ) order by i.sort, i.created_at)
      from public.wl_items i
      where i.list = s.list
        and i.bought_by is null
        and (i.promised_at is null or i.promised_share_id = s.id)
    ), '[]'::jsonb)
  );
end $$;

-- "I'm getting this" from the share page.
create or replace function public.wl_share_claim(p_token text, p_item uuid)
returns boolean
language plpgsql volatile security definer
set search_path = public
as $$
declare s public.wl_shares; n int;
begin
  select * into s from public.wl_shares where token = p_token and revoked_at is null;
  if not found then return false; end if;
  update public.wl_items
     set promised_by_name = s.for_name, promised_at = now(), promised_marked_by = null, promised_share_id = s.id
   where id = p_item and list = s.list and bought_by is null and promised_at is null;
  get diagnostics n = row_count;
  return n = 1;
end $$;

-- "Undo" from the share page — only for things this link claimed and that aren't bought yet.
create or replace function public.wl_share_unclaim(p_token text, p_item uuid)
returns boolean
language plpgsql volatile security definer
set search_path = public
as $$
declare s public.wl_shares; n int;
begin
  select * into s from public.wl_shares where token = p_token and revoked_at is null;
  if not found then return false; end if;
  update public.wl_items
     set promised_by_name = null, promised_at = null, promised_marked_by = null, promised_share_id = null
   where id = p_item and promised_share_id = s.id and bought_by is null;
  get diagnostics n = row_count;
  return n = 1;
end $$;

revoke all on function public.wl_share_view(text) from public;
revoke all on function public.wl_share_claim(text, uuid) from public;
revoke all on function public.wl_share_unclaim(text, uuid) from public;
grant execute on function public.wl_share_view(text) to anon, authenticated;
grant execute on function public.wl_share_claim(text, uuid) to anon, authenticated;
grant execute on function public.wl_share_unclaim(text, uuid) to anon, authenticated;
