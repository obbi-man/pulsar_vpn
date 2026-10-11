import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";

import type {
  Database,
  Plan,
  ProfileRow,
  ServerRow,
  VpnUserRow,
} from "@/lib/supabase/types";
import {
  FREE_USER_LIMIT,
  buildAccessUrl,
  randomConnectionId,
} from "@/lib/supabase/types";
import {
  getSupabaseAnonKey,
  isSupabaseConfigured,
  requireServiceRoleKey,
  requireSupabaseEnv,
} from "@/lib/supabase/env";
import { canAddUser, userLimitForPlan } from "@/lib/billing";

export { isSupabaseConfigured, FREE_USER_LIMIT, buildAccessUrl, randomConnectionId };

/** Cookie-bound server client (RLS as the signed-in user). */
export async function createSupabaseServerClient() {
  const { url, anonKey } = requireSupabaseEnv();
  const cookieStore = await cookies();

  return createServerClient<Database>(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Called from a Server Component — middleware will refresh sessions.
        }
      },
    },
  });
}

/** Service-role client for trusted server routes after auth checks. */
export function getSupabaseServiceClient(): SupabaseClient<Database> {
  const { url } = requireSupabaseEnv();
  const serviceKey = requireServiceRoleKey();
  return createClient<Database>(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function insertServerAfterDeploy(input: {
  adminId: string;
  name?: string;
  ipAddress: string;
  sshPort: number;
  vpnPort?: number;
  secretKey: string;
  id?: string;
}): Promise<ServerRow> {
  const supabase = getSupabaseServiceClient();
  const { data, error } = await supabase
    .from("servers")
    .insert({
      id: input.id,
      admin_id: input.adminId,
      name: input.name ?? `CS ${input.ipAddress}`,
      ip_address: input.ipAddress,
      ssh_port: input.sshPort,
      vpn_port: input.vpnPort ?? 51820,
      secret_key: input.secretKey,
      status: "active",
    })
    .select()
    .single();

  if (error) {
    throw new Error(`Supabase INSERT servers failed: ${error.message}`);
  }
  return data as ServerRow;
}

export async function getLatestServerForAdmin(
  adminId: string,
): Promise<ServerRow | null> {
  const supabase = getSupabaseServiceClient();
  const { data, error } = await supabase
    .from("servers")
    .select("*")
    .eq("admin_id", adminId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`Supabase SELECT servers failed: ${error.message}`);
  }
  return (data as ServerRow | null) ?? null;
}

export async function listVpnUsersForServer(input: {
  adminId: string;
  serverId: string;
}): Promise<VpnUserRow[]> {
  const supabase = getSupabaseServiceClient();
  const { data, error } = await supabase
    .from("vpn_users")
    .select("*")
    .eq("admin_id", input.adminId)
    .eq("server_id", input.serverId)
    .order("created_at", { ascending: false });

  if (error) {
    throw new Error(`Supabase SELECT vpn_users failed: ${error.message}`);
  }
  return (data ?? []) as VpnUserRow[];
}

export async function countVpnUsersForAdmin(adminId: string): Promise<number> {
  const supabase = getSupabaseServiceClient();
  const { count, error } = await supabase
    .from("vpn_users")
    .select("*", { count: "exact", head: true })
    .eq("admin_id", adminId);

  if (error) {
    throw new Error(`Supabase COUNT vpn_users failed: ${error.message}`);
  }
  return count ?? 0;
}

function isProActive(profile: ProfileRow | null): boolean {
  if (!profile || profile.plan !== "pro") return false;
  if (!profile.plan_expires_at) return true;
  return new Date(profile.plan_expires_at).getTime() > Date.now();
}

export async function getOrCreateProfile(adminId: string): Promise<ProfileRow> {
  const supabase = getSupabaseServiceClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", adminId)
    .maybeSingle();

  if (error) {
    throw new Error(`Supabase SELECT profiles failed: ${error.message}`);
  }
  if (data) {
    const row = data as ProfileRow;
    if (row.plan === "pro" && !isProActive(row)) {
      const { data: downgraded, error: upErr } = await supabase
        .from("profiles")
        .update({ plan: "free", plan_expires_at: null, updated_at: new Date().toISOString() })
        .eq("id", adminId)
        .select()
        .single();
      if (upErr) throw new Error(upErr.message);
      return downgraded as ProfileRow;
    }
    return row;
  }

  const { data: created, error: insertError } = await supabase
    .from("profiles")
    .insert({ id: adminId, plan: "free" })
    .select()
    .single();

  if (insertError) {
    // Race: another request created the row.
    const { data: again, error: againErr } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", adminId)
      .single();
    if (againErr || !again) {
      throw new Error(
        insertError.message ?? "Failed to create profile",
      );
    }
    return again as ProfileRow;
  }
  return created as ProfileRow;
}

export async function getAdminPlan(adminId: string): Promise<{
  plan: Plan;
  limit: number | null;
  planExpiresAt: string | null;
}> {
  const profile = await getOrCreateProfile(adminId);
  const plan: Plan = isProActive(profile) ? "pro" : "free";
  return {
    plan,
    limit: userLimitForPlan(plan),
    planExpiresAt: profile.plan_expires_at,
  };
}

export async function upgradeAdminToPro(
  adminId: string,
  opts?: { days?: number },
): Promise<ProfileRow> {
  const days = opts?.days ?? 30;
  const expires = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  const supabase = getSupabaseServiceClient();
  await getOrCreateProfile(adminId);
  const { data, error } = await supabase
    .from("profiles")
    .update({
      plan: "pro",
      plan_expires_at: expires,
      updated_at: new Date().toISOString(),
    })
    .eq("id", adminId)
    .select()
    .single();
  if (error || !data) {
    throw new Error(error?.message ?? "Failed to upgrade plan");
  }
  return data as ProfileRow;
}

export async function createVpnUserRecord(input: {
  adminId: string;
  serverId: string;
  name: string;
}): Promise<
  | {
      ok: true;
      user: VpnUserRow;
      accessUrl: string;
      server: ServerRow;
      plan: Plan;
      limit: number | null;
    }
  | {
      ok: false;
      limitReached: true;
      error: string;
      used: number;
      limit: number;
      plan: Plan;
    }
> {
  const [{ plan, limit }, used] = await Promise.all([
    getAdminPlan(input.adminId),
    countVpnUsersForAdmin(input.adminId),
  ]);
  if (!canAddUser(plan, used)) {
    return {
      ok: false,
      limitReached: true,
      used,
      limit: limit ?? FREE_USER_LIMIT,
      plan,
      error:
        "Достигнут лимит бесплатного тарифа (20 пользователей). Перейдите на Pro, чтобы добавить больше.",
    };
  }

  const supabase = getSupabaseServiceClient();
  const { data: server, error: serverError } = await supabase
    .from("servers")
    .select("*")
    .eq("id", input.serverId)
    .eq("admin_id", input.adminId)
    .single();

  if (serverError || !server) {
    throw new Error(
      serverError?.message ?? "Сервер не найден для текущего администратора",
    );
  }

  const serverRow = server as ServerRow;
  let lastError: string | null = null;

  // Retry on rare connection_id unique collisions.
  for (let attempt = 0; attempt < 5; attempt++) {
    const connectionId = randomConnectionId();
    const { data, error } = await supabase
      .from("vpn_users")
      .insert({
        server_id: input.serverId,
        admin_id: input.adminId,
        name: input.name,
        connection_id: connectionId,
        is_active: true,
      })
      .select()
      .single();

    if (!error && data) {
      const user = data as VpnUserRow;
      return {
        ok: true,
        user,
        server: serverRow,
        plan,
        limit,
        accessUrl: buildAccessUrl({
          secretKey: serverRow.secret_key,
          serverIp: serverRow.ip_address,
          vpnPort: serverRow.vpn_port,
          connectionId: user.connection_id,
        }),
      };
    }
    lastError = error?.message ?? "insert failed";
    if (error?.code !== "23505") break;
  }

  throw new Error(`Supabase INSERT vpn_users failed: ${lastError}`);
}

// Re-export for settings page compatibility
export function getSupabaseAdmin(): SupabaseClient<Database> | null {
  if (!isSupabaseConfigured() || !getSupabaseAnonKey()) return null;
  try {
    return getSupabaseServiceClient();
  } catch {
    return null;
  }
}
