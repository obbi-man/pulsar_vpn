import type { Plan, ServerRow, VpnUserRow } from "@/lib/supabase/types";
import { DEMO_ADMIN_ID } from "@/lib/local-demo";
import {
  FREE_USER_LIMIT,
  buildAccessUrl,
  randomConnectionId,
} from "@/lib/supabase/types";

type MockState = {
  servers: Map<string, ServerRow>;
  users: Map<string, VpnUserRow>;
  plan: Plan;
  planExpiresAt: string | null;
  seeded: boolean;
};

const globalStore = globalThis as typeof globalThis & {
  __csMockStore?: MockState;
};

function store(): MockState {
  if (!globalStore.__csMockStore) {
    globalStore.__csMockStore = {
      servers: new Map(),
      users: new Map(),
      plan: "free",
      planExpiresAt: null,
      seeded: false,
    };
  }
  return globalStore.__csMockStore;
}

function ensureSeed() {
  const s = store();
  if (s.seeded) return;
  s.seeded = true;
  const now = new Date().toISOString();
  const serverId = "11111111-1111-4111-8111-111111111111";
  const secret = "local-demo-secret-key-not-for-prod";
  s.servers.set(serverId, {
    id: serverId,
    admin_id: DEMO_ADMIN_ID,
    name: "Demo VPS (Pulsar local)",
    ip_address: "127.0.0.1",
    ssh_port: 22,
    vpn_port: 51820,
    secret_key: secret,
    status: "active",
    created_at: now,
  });
  // One sample user so the table isn't empty.
  const conn = "aabbccdd";
  const userId = "22222222-2222-4222-8222-222222222222";
  s.users.set(userId, {
    id: userId,
    server_id: serverId,
    admin_id: DEMO_ADMIN_ID,
    name: "demo-client",
    connection_id: conn,
    is_active: true,
    created_at: now,
  });
}

export const mockStore = {
  ensureSeed,

  upsertServer(row: ServerRow) {
    store().servers.set(row.id, row);
  },
  getServer(id: string) {
    ensureSeed();
    return store().servers.get(id) ?? null;
  },
  listServers(adminId: string) {
    ensureSeed();
    return [...store().servers.values()].filter((s) => s.admin_id === adminId);
  },
  latestServer(adminId: string) {
    const list = mockStore.listServers(adminId);
    return list.sort((a, b) => b.created_at.localeCompare(a.created_at))[0] ?? null;
  },
  addUser(user: VpnUserRow) {
    store().users.set(user.id, user);
  },
  listUsers(adminId: string, serverId?: string) {
    ensureSeed();
    return [...store().users.values()]
      .filter(
        (u) =>
          u.admin_id === adminId && (!serverId || u.server_id === serverId),
      )
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
  },
  countUsers(adminId: string) {
    ensureSeed();
    return [...store().users.values()].filter((u) => u.admin_id === adminId)
      .length;
  },
  getPlan() {
    ensureSeed();
    const s = store();
    if (
      s.plan === "pro" &&
      s.planExpiresAt &&
      new Date(s.planExpiresAt).getTime() <= Date.now()
    ) {
      s.plan = "free";
      s.planExpiresAt = null;
    }
    return { plan: s.plan, planExpiresAt: s.planExpiresAt };
  },
  setPro(days = 30) {
    ensureSeed();
    const s = store();
    s.plan = "pro";
    s.planExpiresAt = new Date(
      Date.now() + days * 24 * 60 * 60 * 1000,
    ).toISOString();
    return mockStore.getPlan();
  },
  createUser(adminId: string, serverId: string, name: string) {
    ensureSeed();
    const { plan } = mockStore.getPlan();
    const used = mockStore.countUsers(adminId);
    if (plan !== "pro" && used >= FREE_USER_LIMIT) {
      return {
        ok: false as const,
        limitReached: true as const,
        used,
        limit: FREE_USER_LIMIT,
        plan: "free" as const,
        error:
          "Достигнут лимит бесплатного тарифа (20 пользователей). Перейдите на Pro, чтобы добавить больше.",
      };
    }
    const server = mockStore.getServer(serverId);
    if (!server || server.admin_id !== adminId) {
      throw new Error("Сервер не найден");
    }
    const connectionId = randomConnectionId();
    const user: VpnUserRow = {
      id: crypto.randomUUID(),
      server_id: serverId,
      admin_id: adminId,
      name,
      connection_id: connectionId,
      is_active: true,
      created_at: new Date().toISOString(),
    };
    mockStore.addUser(user);
    return {
      ok: true as const,
      user,
      server,
      plan,
      limit: plan === "pro" ? null : FREE_USER_LIMIT,
      accessUrl: buildAccessUrl({
        secretKey: server.secret_key,
        serverIp: server.ip_address,
        vpnPort: server.vpn_port,
        connectionId,
      }),
    };
  },
};
