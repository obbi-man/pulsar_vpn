import type { Plan } from "@/lib/supabase/types";
import { FREE_USER_LIMIT } from "@/lib/supabase/types";

export type BillingMode = "mock" | "stripe";

export function getBillingMode(): BillingMode {
  const mode = process.env.CS_BILLING_MODE?.trim().toLowerCase();
  if (mode === "stripe") return "stripe";
  return "mock";
}

export function isStripeConfigured(): boolean {
  return Boolean(process.env.STRIPE_SECRET_KEY?.trim());
}

export const PRO_PRICE_RUB = 990;

export type PlanInfo = {
  plan: Plan;
  userLimit: number | null; // null = unlimited
  planExpiresAt: string | null;
  billingMode: BillingMode;
  stripeReady: boolean;
};

export function userLimitForPlan(plan: Plan): number | null {
  return plan === "pro" ? null : FREE_USER_LIMIT;
}

export function canAddUser(plan: Plan, used: number): boolean {
  const limit = userLimitForPlan(plan);
  if (limit === null) return true;
  return used < limit;
}

/** Mock checkout session id — redeemable via POST /api/billing/confirm */
export function createMockCheckoutSession(adminId: string): {
  sessionId: string;
  checkoutUrl: string;
} {
  const sessionId = `cs_mock_${adminId.slice(0, 8)}_${Date.now().toString(36)}`;
  const checkoutUrl = `/dashboard/pricing?checkout=mock&session=${encodeURIComponent(sessionId)}`;
  return { sessionId, checkoutUrl };
}
