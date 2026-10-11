"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

import { isSupabaseConfigured } from "@/lib/supabase/env";

export default function SettingsPage() {
  const supabaseReady = isSupabaseConfigured();
  const [planLabel, setPlanLabel] = useState("…");

  useEffect(() => {
    void (async () => {
      try {
        const res = await fetch("/api/billing/plan");
        const data = (await res.json()) as {
          plan?: string;
          planExpiresAt?: string | null;
        };
        if (!res.ok) {
          setPlanLabel("неизвестно");
          return;
        }
        if (data.plan === "pro") {
          const until = data.planExpiresAt
            ? ` до ${new Date(data.planExpiresAt).toLocaleDateString("ru-RU")}`
            : "";
          setPlanLabel(`Pro${until}`);
        } else {
          setPlanLabel("Free (≤ 20 пользователей)");
        }
      } catch {
        setPlanLabel("неизвестно");
      }
    })();
  }, []);

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-zinc-50">
          Настройки
        </h1>
        <p className="mt-1 text-sm text-zinc-400">
          Параметры панели и интеграций.
        </p>
      </div>

      <div className="space-y-3 rounded-lg border border-zinc-800 bg-zinc-900/40 p-5 text-sm">
        <div className="flex items-center justify-between gap-4">
          <span className="text-zinc-300">Supabase</span>
          <span
            className={
              supabaseReady ? "text-emerald-400" : "text-amber-400"
            }
          >
            {supabaseReady ? "Подключён" : "Не настроен (.env.local)"}
          </span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span className="text-zinc-300">Протокол</span>
          <span className="text-zinc-400">ChaCha20-Poly1305 / UDP datapath</span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span className="text-zinc-300">Тариф</span>
          <span className="text-zinc-400">
            {planLabel}{" "}
            <Link href="/dashboard/pricing" className="text-zinc-200 underline">
              изменить
            </Link>
          </span>
        </div>
      </div>
    </div>
  );
}
