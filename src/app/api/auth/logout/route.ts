import { NextResponse } from "next/server";

import { DEMO_COOKIE, isLocalDemoEnabled } from "@/lib/local-demo";
import {
  createSupabaseServerClient,
  isSupabaseConfigured,
} from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST() {
  const res = NextResponse.json({ ok: true });
  if (isLocalDemoEnabled()) {
    res.cookies.set(DEMO_COOKIE, "", {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
      maxAge: 0,
    });
  }
  if (isSupabaseConfigured()) {
    try {
      const supabase = await createSupabaseServerClient();
      await supabase.auth.signOut();
    } catch {
      // ignore
    }
  }
  return res;
}
