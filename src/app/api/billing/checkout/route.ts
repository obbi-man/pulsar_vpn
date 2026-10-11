import { NextResponse } from "next/server";

import { AuthRequiredError, getAuthenticatedAdminId, useMockDataLayer } from "@/lib/auth";
import {
  createMockCheckoutSession,
  getBillingMode,
  isStripeConfigured,
  PRO_PRICE_RUB,
} from "@/lib/billing";
import { mockStore } from "@/lib/supabase/mock-store";
import { getAdminPlan } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Starts Pro checkout.
 * - CS_BILLING_MODE=mock (default): returns a mock checkout URL; confirm via /api/billing/confirm
 * - CS_BILLING_MODE=stripe + STRIPE_SECRET_KEY: placeholder until Stripe keys exist
 */
export async function POST() {
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
    const plan = useMockDataLayer()
      ? mockStore.getPlan().plan
      : (await getAdminPlan(adminId)).plan;
    if (plan === "pro") {
      return NextResponse.json(
        { error: "У вас уже активен Pro", plan },
        { status: 400 },
      );
    }

    const mode = getBillingMode();
    if (mode === "stripe") {
      if (!isStripeConfigured()) {
        return NextResponse.json(
          {
            error:
              "Stripe не настроен. Укажите STRIPE_SECRET_KEY или используйте CS_BILLING_MODE=mock.",
            code: "STRIPE_NOT_CONFIGURED",
          },
          { status: 503 },
        );
      }
      // Real Stripe Checkout Session would be created here with STRIPE_SECRET_KEY.
      return NextResponse.json(
        {
          error:
            "Stripe Checkout ещё не подключён в этой сборке. Используйте mock или дождитесь интеграции.",
          code: "STRIPE_TODO",
          priceRub: PRO_PRICE_RUB,
        },
        { status: 501 },
      );
    }

    const session = createMockCheckoutSession(adminId);
    return NextResponse.json({
      mode: "mock",
      sessionId: session.sessionId,
      checkoutUrl: session.checkoutUrl,
      priceRub: PRO_PRICE_RUB,
      message:
        "Mock checkout: откройте checkoutUrl и подтвердите оплату кнопкой на странице тарифов.",
    });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Ошибка checkout" },
      { status: 500 },
    );
  }
}
