"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Check, Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

type PlanState = {
  plan: "free" | "pro";
  used: number;
  limit: number | null;
  planExpiresAt: string | null;
  priceRub: number;
  billingMode: "mock" | "stripe";
  stripeReady: boolean;
};

function readCheckoutQuery() {
  if (typeof window === "undefined") {
    return { checkout: null as string | null, session: null as string | null };
  }
  const q = new URLSearchParams(window.location.search);
  return { checkout: q.get("checkout"), session: q.get("session") };
}

export default function PricingPage() {
  const [info, setInfo] = useState<PlanState | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState({ checkout: null as string | null, session: null as string | null });

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/billing/plan");
      const data = (await res.json()) as PlanState & { error?: string };
      if (!res.ok) throw new Error(data.error ?? "Не удалось загрузить тариф");
      setInfo(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
    const q = readCheckoutQuery();
    setQuery(q);
    if (q.checkout === "mock" && q.session) {
      setMessage(
        `Mock-сессия ${q.session} готова. Нажмите «Подтвердить оплату (mock)», чтобы активировать Pro.`,
      );
    }
  }, [load]);

  const showMockConfirm = useMemo(
    () => query.checkout === "mock" && Boolean(query.session),
    [query],
  );

  async function startCheckout() {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      const res = await fetch("/api/billing/checkout", { method: "POST" });
      const data = (await res.json()) as {
        error?: string;
        checkoutUrl?: string;
        sessionId?: string;
        message?: string;
      };
      if (!res.ok) throw new Error(data.error ?? "Checkout failed");
      if (data.checkoutUrl) {
        window.location.href = data.checkoutUrl;
        return;
      }
      setMessage(data.message ?? "Checkout создан");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setBusy(false);
    }
  }

  async function confirmMock() {
    const session = query.session;
    if (!session) {
      setError("Нет session в URL — сначала нажмите «Обновить до Pro»");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/billing/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sessionId: session }),
      });
      const data = (await res.json()) as { error?: string; message?: string };
      if (!res.ok) throw new Error(data.error ?? "Confirm failed");
      setMessage(data.message ?? "Pro активирован");
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setBusy(false);
    }
  }

  const isPro = info?.plan === "pro";

  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-zinc-50">Тарифы</h1>
        <p className="mt-1 text-sm text-zinc-400">
          Free до 20 пользователей. Сверх лимита — Pro.
        </p>
      </div>

      {loading && (
        <div className="flex items-center gap-2 text-sm text-zinc-400">
          <Loader2 className="size-4 animate-spin" /> Загрузка тарифа…
        </div>
      )}
      {error && (
        <p className="rounded-md border border-red-900/40 bg-red-950/30 px-3 py-2 text-sm text-red-200">
          {error}
        </p>
      )}
      {message && (
        <p className="rounded-md border border-emerald-900/40 bg-emerald-950/30 px-3 py-2 text-sm text-emerald-200">
          {message}
        </p>
      )}

      {info && (
        <p className="text-sm text-zinc-400">
          Сейчас:{" "}
          <Badge className="align-middle">
            {isPro ? "Pro" : "Free"}
          </Badge>
          {" · "}
          {info.used}
          {info.limit != null ? ` / ${info.limit}` : " / ∞"} пользователей
          {info.planExpiresAt && isPro
            ? ` · до ${new Date(info.planExpiresAt).toLocaleDateString("ru-RU")}`
            : null}
          {" · "}
          billing: {info.billingMode}
        </p>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 p-6">
          <p className="text-sm text-zinc-400">Free</p>
          <p className="mt-2 text-3xl font-semibold text-zinc-50">0 ₽</p>
          <ul className="mt-4 space-y-2 text-sm text-zinc-300">
            <li className="flex gap-2">
              <Check className="size-4 text-emerald-400" /> До 20 пользователей
            </li>
            <li className="flex gap-2">
              <Check className="size-4 text-emerald-400" /> Один VPS / Pulsar
            </li>
            <li className="flex gap-2">
              <Check className="size-4 text-emerald-400" /> Obfuscated UDP
            </li>
          </ul>
          <Button
            disabled
            className="mt-6 w-full border border-zinc-700 bg-transparent text-zinc-400"
          >
            {!isPro ? "Текущий тариф" : "Базовый тариф"}
          </Button>
        </div>

        <div className="rounded-lg border border-zinc-600 bg-zinc-900/60 p-6">
          <p className="text-sm text-zinc-400">Pro</p>
          <p className="mt-2 text-3xl font-semibold text-zinc-50">
            {info?.priceRub ?? 990} ₽
            <span className="text-base font-normal text-zinc-500">/мес</span>
          </p>
          <ul className="mt-4 space-y-2 text-sm text-zinc-300">
            <li className="flex gap-2">
              <Check className="size-4 text-emerald-400" /> Безлимит пользователей
            </li>
            <li className="flex gap-2">
              <Check className="size-4 text-emerald-400" /> Несколько серверов
            </li>
            <li className="flex gap-2">
              <Check className="size-4 text-emerald-400" /> Приоритетная поддержка
            </li>
          </ul>
          {isPro ? (
            <Button
              disabled
              className="mt-6 w-full border border-zinc-700 bg-transparent text-zinc-400"
            >
              Уже Pro
            </Button>
          ) : (
            <div className="mt-6 space-y-2">
              <Button
                disabled={busy}
                onClick={() => void startCheckout()}
                className="w-full bg-zinc-100 text-zinc-950 hover:bg-white"
              >
                {busy ? (
                  <Loader2 className="size-4 animate-spin" />
                ) : (
                  "Обновить до Pro"
                )}
              </Button>
              {showMockConfirm && (
                <Button
                  disabled={busy}
                  variant="outline"
                  onClick={() => void confirmMock()}
                  className="w-full border-zinc-700"
                >
                  Подтвердить оплату (mock)
                </Button>
              )}
            </div>
          )}
        </div>
      </div>

      <p className="text-xs text-zinc-500">
        Платежи: по умолчанию{" "}
        <code className="text-zinc-400">CS_BILLING_MODE=mock</code> (без
        секретов). Для Stripe задайте{" "}
        <code className="text-zinc-400">CS_BILLING_MODE=stripe</code> и{" "}
        <code className="text-zinc-400">STRIPE_SECRET_KEY</code>.
      </p>
    </div>
  );
}
