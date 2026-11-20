-- Sizes on product links (e.g. "M", "UK 10", "32W 30L"). Run once in the SQL Editor,
-- AFTER 2026-11-20-share-links.sql. Safe to re-run.

alter table public.wl_options add column if not exists size text
  check (size is null or length(size) between 1 and 30);

-- Show sizes on the share page too (same function as before, plus 'size').
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
            'price', o.price, 'size', o.size, 'top', o.id = i.top_option_id
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
