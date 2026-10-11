import { NextResponse } from "next/server";
import { z } from "zod";

import {
  DEMO_ADMIN_EMAIL,
  DEMO_ADMIN_EMAIL_LEGACY,
  DEMO_ADMIN_PASSWORD,
  DEMO_COOKIE,
  demoCookieValue,
  isLocalDemoEnabled,
} from "@/lib/local-demo";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const bodySchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

/** Cookie login for CS_LOCAL_DEMO=1 (no Supabase). */
export async function POST(request: Request) {
  if (!isLocalDemoEnabled()) {
    return NextResponse.json(
      { error: "Локальный демо-режим выключен (CS_LOCAL_DEMO≠1)" },
      { status: 403 },
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
    return NextResponse.json({ error: "Неверные данные" }, { status: 400 });
  }

  const email = parsed.data.email.trim().toLowerCase();
  const emailOk =
    email === DEMO_ADMIN_EMAIL || email === DEMO_ADMIN_EMAIL_LEGACY;
  if (!emailOk || parsed.data.password !== DEMO_ADMIN_PASSWORD) {
    return NextResponse.json(
      { error: "Неверный email или пароль (демо)" },
      { status: 401 },
    );
  }

  const res = NextResponse.json({
    ok: true,
    email: DEMO_ADMIN_EMAIL,
    mode: "local-demo",
    product: "Pulsar VPN",
  });
  res.cookies.set(DEMO_COOKIE, demoCookieValue(), {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7,
  });
  return res;
}
