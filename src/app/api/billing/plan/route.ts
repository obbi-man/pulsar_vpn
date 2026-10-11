import { NextResponse } from "next/server";

import { AuthRequiredError, getAuthenticatedAdminId, useMockDataLayer } from "@/lib/auth";
import {
  getBillingMode,
  isStripeConfigured,
  PRO_PRICE_RUB,
  userLimitForPlan,
} from "@/lib/billing";
import { FREE_USER_LIMIT } from "@/lib/supabase/types";
import { mockStore } from "@/lib/supabase/mock-store";
import {
  countVpnUsersForAdmin,
  getAdminPlan,
} from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
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

  try {
    if (useMockDataLayer()) {
      mockStore.ensureSeed();
      const { plan, planExpiresAt } = mockStore.getPlan();
      const used = mockStore.countUsers(adminId);
      const limit = plan === "pro" ? null : FREE_USER_LIMIT;
      return NextResponse.json({
        plan,
        used,
        limit,
        planExpiresAt,
        priceRub: PRO_PRICE_RUB,
        billingMode: getBillingMode(),
        stripeReady: isStripeConfigured(),
        canAddUsers: limit === null || used < limit,
        localDemo: true,
      });
    }

    const [{ plan, planExpiresAt }, used] = await Promise.all([
      getAdminPlan(adminId),
      countVpnUsersForAdmin(adminId),
    ]);
    const limit = userLimitForPlan(plan);
    return NextResponse.json({
      plan,
      used,
      limit,
      planExpiresAt,
      priceRub: PRO_PRICE_RUB,
      billingMode: getBillingMode(),
      stripeReady: isStripeConfigured(),
      canAddUsers: limit === null || used < limit,
    });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Ошибка тарифа" },
      { status: 500 },
    );
  }
}
