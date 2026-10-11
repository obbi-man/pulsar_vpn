import { cookies } from "next/headers";

import {
  DEMO_ADMIN_EMAIL,
  DEMO_ADMIN_ID,
  DEMO_COOKIE,
  demoCookieValue,
  isLocalDemoEnabled,
} from "@/lib/local-demo";
import { createSupabaseServerClient, isSupabaseConfigured } from "@/lib/supabase/server";

export class AuthRequiredError extends Error {
  constructor(message = "Требуется авторизация") {
    super(message);
    this.name = "AuthRequiredError";
  }
}

async function hasDemoSession(): Promise<boolean> {
  if (!isLocalDemoEnabled()) return false;
  const jar = await cookies();
  return jar.get(DEMO_COOKIE)?.value === demoCookieValue();
}

/** Returns authenticated Supabase user id (auth.uid()) or local demo admin. */
export async function getAuthenticatedAdminId(): Promise<string> {
  if (await hasDemoSession()) {
    return DEMO_ADMIN_ID;
  }

  if (!isSupabaseConfigured()) {
    throw new AuthRequiredError(
      isLocalDemoEnabled()
        ? "Войдите демо-аккаунтом на /login"
        : "Supabase не настроен. Задайте NEXT_PUBLIC_SUPABASE_URL и NEXT_PUBLIC_SUPABASE_ANON_KEY (или CS_LOCAL_DEMO=1).",
    );
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user?.id) {
    throw new AuthRequiredError("Войдите в панель, чтобы продолжить");
  }
  return data.user.id;
}

export async function getOptionalSessionUser(): Promise<{
  id: string;
  email: string | null;
} | null> {
  if (await hasDemoSession()) {
    return { id: DEMO_ADMIN_ID, email: DEMO_ADMIN_EMAIL };
  }
  if (!isSupabaseConfigured()) return null;
  try {
    const supabase = await createSupabaseServerClient();
    const { data } = await supabase.auth.getUser();
    if (!data.user) return null;
    return { id: data.user.id, email: data.user.email ?? null };
  } catch {
    return null;
  }
}

export function useMockDataLayer(): boolean {
  return isLocalDemoEnabled() || !isSupabaseConfigured();
}
