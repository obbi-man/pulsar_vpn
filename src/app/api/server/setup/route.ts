import { NextResponse } from "next/server";
import { z } from "zod";
import { randomUUID } from "node:crypto";

import { AuthRequiredError, getAuthenticatedAdminId, useMockDataLayer } from "@/lib/auth";
import { insertServerAfterDeploy } from "@/lib/supabase/server";
import { mockStore } from "@/lib/supabase/mock-store";
import { provisionVps } from "@/lib/ssh/provision";
import { isLocalDemoEnabled } from "@/lib/local-demo";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const setupBodySchema = z.object({
  ip: z.string().min(1, "IP обязателен"),
  host: z.string().min(1).optional(),
  port: z.coerce.number().int().min(1).max(65535).default(22),
  username: z.string().min(1).default("root"),
  login: z.string().min(1).optional(),
  password: z.string().min(1, "Пароль обязателен"),
  name: z.string().trim().max(80).optional(),
});

type ApiErrorBody = {
  error: string;
  code:
    | "VALIDATION_ERROR"
    | "SSH_ERROR"
    | "DEPLOY_ERROR"
    | "AUTH_ERROR"
    | "SUPABASE_ERROR"
    | "INTERNAL_ERROR";
  details?: string;
};

function jsonError(
  status: number,
  body: ApiErrorBody,
): NextResponse<ApiErrorBody> {
  return NextResponse.json(body, { status });
}

export async function POST(request: Request) {
  let json: unknown;
  try {
    json = await request.json();
  } catch {
    return jsonError(400, {
      error: "Некорректный JSON в теле запроса",
      code: "VALIDATION_ERROR",
    });
  }

  const parsed = setupBodySchema.safeParse(json);
  if (!parsed.success) {
    return jsonError(400, {
      error: "Неверные параметры подключения",
      code: "VALIDATION_ERROR",
      details: parsed.error.issues.map((i) => i.message).join("; "),
    });
  }

  const host = parsed.data.host ?? parsed.data.ip;
  const username = parsed.data.login ?? parsed.data.username;
  const { port, password, name } = parsed.data;

  let adminId: string;
  try {
    adminId = await getAuthenticatedAdminId();
  } catch (err) {
    return jsonError(401, {
      error:
        err instanceof AuthRequiredError
          ? err.message
          : "Требуется авторизация администратора",
      code: "AUTH_ERROR",
      details: err instanceof Error ? err.message : undefined,
    });
  }

  // Local demo: record a mock server without SSH (no VPS required).
  if (isLocalDemoEnabled() && useMockDataLayer()) {
    const secretKey = `pulsar-demo-${randomUUID().slice(0, 8)}`;
    const server = {
      id: randomUUID(),
      admin_id: adminId,
      name: name ?? `Pulsar ${host}`,
      ip_address: host,
      ssh_port: port,
      vpn_port: 51820,
      secret_key: secretKey,
      status: "active" as const,
      created_at: new Date().toISOString(),
    };
    mockStore.upsertServer(server);
    return NextResponse.json({
      ok: true,
      localDemo: true,
      server: {
        id: server.id,
        name: server.name,
        ip_address: server.ip_address,
        ssh_port: server.ssh_port,
        vpn_port: server.vpn_port,
        status: server.status,
        created_at: server.created_at,
      },
      message:
        "Локальный демо: сервер записан без SSH. На реальном VPS Pulsar поднимется через Docker.",
    });
  }

  try {
    const result = await provisionVps({
      host,
      port,
      username,
      password,
    });

    const server = await insertServerAfterDeploy({
      id: result.serverUuid,
      adminId,
      name: name ?? `Pulsar ${host}`,
      ipAddress: host,
      sshPort: port,
      vpnPort: 51820,
      secretKey: result.secretKey,
    });

    return NextResponse.json(
      {
        ok: true,
        server: {
          id: server.id,
          name: server.name,
          ip_address: server.ip_address,
          ssh_port: server.ssh_port,
          vpn_port: server.vpn_port,
          status: server.status,
          created_at: server.created_at,
        },
        message: "Pulsar VPN успешно развёрнут на вашем VPS",
      },
      { status: 200 },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Неизвестная ошибка";

    if (message.includes("Supabase")) {
      return jsonError(500, {
        error: "Не удалось сохранить сервер в Supabase",
        code: "SUPABASE_ERROR",
        details: message,
      });
    }

    const isSsh =
      message.toLowerCase().includes("ssh") ||
      message.toLowerCase().includes("timed out") ||
      message.toLowerCase().includes("authentication") ||
      message.toLowerCase().includes("econnrefused");

    if (
      isSsh &&
      !message.includes("SUCCESS_DEPLOYS") &&
      !message.includes("Deploy script")
    ) {
      return jsonError(502, {
        error: "Не удалось подключиться к VPS по SSH",
        code: "SSH_ERROR",
        details: message,
      });
    }

    if (message.includes("Deploy") || message.includes("SUCCESS_DEPLOYS")) {
      return jsonError(502, {
        error: "Ошибка развёртывания Pulsar на сервере",
        code: "DEPLOY_ERROR",
        details: message,
      });
    }

    return jsonError(500, {
      error: "Внутренняя ошибка при настройке сервера",
      code: "INTERNAL_ERROR",
      details: message,
    });
  }
}
