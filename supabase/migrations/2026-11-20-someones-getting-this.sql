-- "Someone's getting this": run once in the Supabase SQL Editor (safe to re-run).
-- Adds who promised an item (optional name), when, and which of you marked it.
alter table public.wl_items add column if not exists promised_by_name text
  check (promised_by_name is null or length(promised_by_name) between 1 and 60);
alter table public.wl_items add column if not exists promised_at timestamptz;
alter table public.wl_items add column if not exists promised_marked_by uuid
  references public.wl_members(user_id) on delete set null;
