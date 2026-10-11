import { NextResponse } from "next/server";
import { z } from "zod";

import { AuthRequiredError, getAuthenticatedAdminId, useMockDataLayer } from "@/lib/auth";
import { FREE_USER_LIMIT } from "@/lib/supabase/types";
import { mockStore } from "@/lib/supabase/mock-store";
import {
  buildAccessUrl,
  countVpnUsersForAdmin,
  createVpnUserRecord,
  getAdminPlan,
  getLatestServerForAdmin,
  getSupabaseServiceClient,
  listVpnUsersForServer,
} from "@/lib/supabase/server";
import type { ServerRow } from "@/lib/supabase/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const createSchema = z.object({
  name: z.string().trim().min(1, "Имя обязательно").max(64),
  serverId: z.string().uuid().optional(),
});

function authError(err: unknown) {
  return NextResponse.json(
    {
      error:
        err instanceof AuthRequiredError
          ? err.message
          : "Требуется авторизация",
      code: "AUTH_ERROR",
    },
    { status: 401 },
  );
}

async function resolveServer(
  adminId: string,
  serverId?: string | null,
): Promise<ServerRow | null> {
  if (useMockDataLayer()) {
    if (serverId) return mockStore.getServer(serverId);
    return mockStore.latestServer(adminId);
  }
  if (serverId) {
    const sb = getSupabaseServiceClient();
    const { data, error } = await sb
      .from("servers")
      .select("*")
      .eq("id", serverId)
      .eq("admin_id", adminId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return (data as ServerRow | null) ?? null;
  }
  return getLatestServerForAdmin(adminId);
}

export async function GET(request: Request) {
  let adminId: string;
  try {
    adminId = await getAuthenticatedAdminId();
  } catch (err) {
    return authError(err);
  }

  try {
    const serverId = new URL(request.url).searchParams.get("serverId");

    if (useMockDataLayer()) {
      mockStore.ensureSeed();
      const activeServer = await resolveServer(adminId, serverId);
      const { plan, planExpiresAt } = mockStore.getPlan();
      const limit = plan === "pro" ? null : FREE_USER_LIMIT;
      if (!activeServer) {
        return NextResponse.json({
          users: [],
          used: 0,
          limit,
          plan,
          planExpiresAt,
          server: null,
          message: "Сначала подключите сервер на вкладке «Сервер»",
        });
      }
      const users = mockStore.listUsers(adminId, activeServer.id);
      const used = mockStore.countUsers(adminId);
      return NextResponse.json({
        users: users.map((u) => ({
          ...u,
          access_url: buildAccessUrl({
            secretKey: activeServer.secret_key,
            serverIp: activeServer.ip_address,
            vpnPort: activeServer.vpn_port,
            connectionId: u.connection_id,
          }),
          status: u.is_active ? ("active" as const) : ("disabled" as const),
        })),
        used,
        limit,
        plan,
        server: {
          id: activeServer.id,
          name: activeServer.name,
          ip_address: activeServer.ip_address,
          vpn_port: activeServer.vpn_port,
        },
      });
    }

    const activeServer = await resolveServer(adminId, serverId);
    const { plan, limit } = await getAdminPlan(adminId);

    if (!activeServer) {
      return NextResponse.json({
        users: [],
        used: 0,
        limit,
        plan,
        server: null,
        message: "Сначала подключите сервер на вкладке «Сервер»",
      });
    }

    const [users, used] = await Promise.all([
      listVpnUsersForServer({
        adminId,
        serverId: activeServer.id,
      }),
      countVpnUsersForAdmin(adminId),
    ]);

    const enriched = users.map((u) => ({
      ...u,
      access_url: buildAccessUrl({
        secretKey: activeServer.secret_key,
        serverIp: activeServer.ip_address,
        vpnPort: activeServer.vpn_port,
        connectionId: u.connection_id,
      }),
      status: u.is_active ? ("active" as const) : ("disabled" as const),
    }));

    return NextResponse.json({
      users: enriched,
      used,
      limit,
      plan,
      server: {
        id: activeServer.id,
        name: activeServer.name,
        ip_address: activeServer.ip_address,
        vpn_port: activeServer.vpn_port,
      },
    });
  } catch (err) {
    return NextResponse.json(
      {
        error: err instanceof Error ? err.message : "Ошибка загрузки",
        code: "SUPABASE_ERROR",
      },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  let adminId: string;
  try {
    adminId = await getAuthenticatedAdminId();
  } catch (err) {
    return authError(err);
  }

  let json: unknown;
  try {
    json = await request.json();
  } catch {
    return NextResponse.json({ error: "Некорректный JSON" }, { status: 400 });
  }

  const parsed = createSchema.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "Неверные данные" },
      { status: 400 },
    );
  }

  try {
    const server = await resolveServer(adminId, parsed.data.serverId);
    if (!server) {
      return NextResponse.json(
        { error: "Нет активного сервера. Сначала выполните setup VPS." },
        { status: 400 },
      );
    }

    if (useMockDataLayer()) {
      const result = mockStore.createUser(adminId, server.id, parsed.data.name);
      if (!result.ok) {
        return NextResponse.json(
          {
            error: result.error,
            limitReached: true,
            used: result.used,
            limit: result.limit,
            plan: result.plan,
          },
          { status: 403 },
        );
      }
      return NextResponse.json(
        {
          user: {
            ...result.user,
            access_url: result.accessUrl,
            status: result.user.is_active ? "active" : "disabled",
          },
          access_url: result.accessUrl,
          limit: result.limit ?? FREE_USER_LIMIT,
          plan: result.plan,
        },
        { status: 201 },
      );
    }

    const result = await createVpnUserRecord({
      adminId,
      serverId: server.id,
      name: parsed.data.name,
    });

    if (!result.ok) {
      return NextResponse.json(
        {
          error: result.error,
          limitReached: true,
          used: result.used,
          limit: result.limit,
          plan: result.plan,
        },
        { status: 403 },
      );
    }

    return NextResponse.json(
      {
        user: {
          ...result.user,
          access_url: result.accessUrl,
          status: result.user.is_active ? "active" : "disabled",
        },
        access_url: result.accessUrl,
        limit: result.limit ?? FREE_USER_LIMIT,
        plan: result.plan,
      },
      { status: 201 },
    );
  } catch (err) {
    return NextResponse.json(
      {
        error: err instanceof Error ? err.message : "Ошибка создания",
        code: "SUPABASE_ERROR",
      },
      { status: 500 },
    );
  }
}
