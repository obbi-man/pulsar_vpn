/** Local panel testing without Supabase / VPS. Enable with CS_LOCAL_DEMO=1. */

export const DEMO_COOKIE = "cs_demo_session";
export const DEMO_ADMIN_ID = "00000000-0000-4000-8000-000000000001";
export const DEMO_ADMIN_EMAIL = "admin@pulsar.local";
/** Legacy demo email still accepted during rename. */
export const DEMO_ADMIN_EMAIL_LEGACY = "admin@customshield.local";
export const DEMO_ADMIN_PASSWORD = "demo-admin";

export function isLocalDemoEnabled(): boolean {
  const v = process.env.CS_LOCAL_DEMO?.trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes";
}

export function demoCookieValue(): string {
  return "demo";
}
