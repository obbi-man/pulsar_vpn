export function getSupabaseUrl(): string | undefined {
  return process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() || undefined;
}

export function getSupabaseAnonKey(): string | undefined {
  return process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim() || undefined;
}

export function getSupabaseServiceRoleKey(): string | undefined {
  return process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() || undefined;
}

export function isSupabaseConfigured(): boolean {
  return Boolean(getSupabaseUrl() && getSupabaseAnonKey());
}

export function requireSupabaseEnv(): {
  url: string;
  anonKey: string;
} {
  const url = getSupabaseUrl();
  const anonKey = getSupabaseAnonKey();
  if (!url || !anonKey) {
    throw new Error(
      "Supabase не настроен: задайте NEXT_PUBLIC_SUPABASE_URL и NEXT_PUBLIC_SUPABASE_ANON_KEY в .env.local",
    );
  }
  return { url, anonKey };
}

export function requireServiceRoleKey(): string {
  const key = getSupabaseServiceRoleKey();
  if (!key) {
    throw new Error(
      "Supabase не настроен: задайте SUPABASE_SERVICE_ROLE_KEY в .env.local",
    );
  }
  return key;
}
