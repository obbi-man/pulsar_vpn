-- Admin profiles + plan (Free / Pro) for CustomShield billing groundwork.
-- Apply after 20261006_init.sql

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  plan text not null default 'free'
    check (plan in ('free', 'pro')),
  plan_expires_at timestamptz,
  stripe_customer_id text,
  updated_at timestamptz not null default now()
);

create index if not exists profiles_plan_idx on public.profiles (plan);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- Auto-create free profile on signup
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, plan)
  values (new.id, 'free')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute function public.handle_new_user_profile();
