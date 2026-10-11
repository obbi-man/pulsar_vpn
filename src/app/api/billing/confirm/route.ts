import { NextResponse } from "next/server";
import { z } from "zod";

import { AuthRequiredError, getAuthenticatedAdminId, useMockDataLayer } from "@/lib/auth";
import { getBillingMode } from "@/lib/billing";
import { mockStore } from "@/lib/supabase/mock-store";
import { upgradeAdminToPro } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const bodySchema = z.object({
  sessionId: z.string().min(8).max(128),
});

/** Completes mock Pro checkout (no real charge). */
export async function POST(request: Request) {
  let adminId: string;
  try {
    adminId = await getAuthenticatedAdminId();
  } catch (err) {
    return NextResponse.json(
      {
        error:
          err instanceof AuthRequiredError
            ? err.message
            : "Требуется авторизация",
      },
      { status: 401 },
    );
  }

  if (getBillingMode() !== "mock") {
    return NextResponse.json(
      { error: "Confirm доступен только в CS_BILLING_MODE=mock" },
      { status: 400 },
    );
  }

  let json: unknown;
  try {
    json = await request.json();
  } catch {
    return NextResponse.json({ error: "Некорректный JSON" }, { status: 400 });
  }

  const parsed = bodySchema.safeParse(json);
  if (!parsed.success) {
    return NextResponse.json({ error: "Неверный sessionId" }, { status: 400 });
  }

  if (!parsed.data.sessionId.startsWith("cs_mock_")) {
    return NextResponse.json(
      { error: "Неизвестная mock-сессия" },
      { status: 400 },
    );
  }

  try {
    if (useMockDataLayer()) {
      const { plan, planExpiresAt } = mockStore.setPro(30);
      return NextResponse.json({
        ok: true,
        plan,
        planExpiresAt,
        message: "Pro активирован на 30 дней (mock checkout / local demo).",
      });
    }

    const profile = await upgradeAdminToPro(adminId, { days: 30 });
    return NextResponse.json({
      ok: true,
      plan: profile.plan,
      planExpiresAt: profile.plan_expires_at,
      message: "Pro активирован на 30 дней (mock checkout).",
    });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Ошибка активации" },
      { status: 500 },
    );
  }
}
