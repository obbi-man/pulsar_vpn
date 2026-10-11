-- CustomShield initial schema + RLS
-- Apply in Supabase SQL Editor or: supabase db push

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- servers
-- ---------------------------------------------------------------------------
create table if not exists public.servers (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users (id) on delete cascade,
  name text not null default 'CustomShield Server',
  ip_address text not null,
  ssh_port integer not null default 22 check (ssh_port > 0 and ssh_port <= 65535),
  vpn_port integer not null default 51820 check (vpn_port > 0 and vpn_port <= 65535),
  secret_key text not null,
  status text not null default 'active'
    check (status in ('pending', 'active', 'error')),
  created_at timestamptz not null default now()
);

create index if not exists servers_admin_id_idx on public.servers (admin_id);
create index if not exists servers_admin_created_idx on public.servers (admin_id, created_at desc);

-- ---------------------------------------------------------------------------
-- vpn_users
-- ---------------------------------------------------------------------------
create table if not exists public.vpn_users (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers (id) on delete cascade,
  admin_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  connection_id text not null unique
    check (connection_id ~ '^[0-9a-f]{8}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists vpn_users_admin_id_idx on public.vpn_users (admin_id);
create index if not exists vpn_users_server_id_idx on public.vpn_users (server_id);
create index if not exists vpn_users_admin_server_idx on public.vpn_users (admin_id, server_id);

-- ---------------------------------------------------------------------------
-- Row Level Security: admin full CRUD only on own rows
-- ---------------------------------------------------------------------------
alter table public.servers enable row level security;
alter table public.vpn_users enable row level security;

-- servers policies
drop policy if exists "servers_select_own" on public.servers;
create policy "servers_select_own"
  on public.servers for select
  using (admin_id = auth.uid());

drop policy if exists "servers_insert_own" on public.servers;
create policy "servers_insert_own"
  on public.servers for insert
  with check (admin_id = auth.uid());

drop policy if exists "servers_update_own" on public.servers;
create policy "servers_update_own"
  on public.servers for update
  using (admin_id = auth.uid())
  with check (admin_id = auth.uid());

drop policy if exists "servers_delete_own" on public.servers;
create policy "servers_delete_own"
  on public.servers for delete
  using (admin_id = auth.uid());

-- vpn_users policies
drop policy if exists "vpn_users_select_own" on public.vpn_users;
create policy "vpn_users_select_own"
  on public.vpn_users for select
  using (admin_id = auth.uid());

drop policy if exists "vpn_users_insert_own" on public.vpn_users;
create policy "vpn_users_insert_own"
  on public.vpn_users for insert
  with check (admin_id = auth.uid());

drop policy if exists "vpn_users_update_own" on public.vpn_users;
create policy "vpn_users_update_own"
  on public.vpn_users for update
  using (admin_id = auth.uid())
  with check (admin_id = auth.uid());

drop policy if exists "vpn_users_delete_own" on public.vpn_users;
create policy "vpn_users_delete_own"
  on public.vpn_users for delete
  using (admin_id = auth.uid());
