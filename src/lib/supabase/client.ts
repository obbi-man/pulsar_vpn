"use client";

import { createBrowserClient } from "@supabase/ssr";

import type { Database } from "@/lib/supabase/types";
import { getSupabaseAnonKey, getSupabaseUrl } from "@/lib/supabase/env";

export function createSupabaseBrowserClient() {
  const url = getSupabaseUrl();
  const anonKey = getSupabaseAnonKey();
  if (!url || !anonKey) {
    throw new Error(
      "Supabase не настроен: NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY",
    );
  }
  return createBrowserClient<Database>(url, anonKey);
}
