"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { Server, Users, CreditCard, Settings, Shield } from "lucide-react";

import { cn } from "@/lib/utils";

const nav = [
  { href: "/dashboard/server", label: "Сервер", icon: Server },
  { href: "/dashboard/users", label: "Пользователи", icon: Users },
  { href: "/dashboard/pricing", label: "Тарифы", icon: CreditCard },
  { href: "/dashboard/settings", label: "Настройки", icon: Settings },
] as const;

export function DashboardSidebar() {
  const pathname = usePathname();
  const [planHint, setPlanHint] = useState("Free ≤ 20 пользователей");

  useEffect(() => {
    void (async () => {
      try {
        const res = await fetch("/api/billing/plan");
        const data = (await res.json()) as { plan?: string };
        if (res.ok && data.plan === "pro") {
          setPlanHint("Pro · безлимит");
        }
      } catch {
        // keep default
      }
    })();
  }, []);

  return (
    <aside className="flex w-60 shrink-0 flex-col border-r border-zinc-800 bg-zinc-950">
      <div className="flex h-14 items-center gap-2 border-b border-zinc-800 px-4">
        <Shield className="size-5 text-zinc-100" />
        <span className="text-sm font-semibold tracking-wide text-zinc-50">
          Pulsar VPN
        </span>
      </div>
      <nav className="flex flex-1 flex-col gap-1 p-3">
        {nav.map((item) => {
          const active =
            pathname === item.href || pathname.startsWith(`${item.href}/`);
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-2.5 rounded-md px-3 py-2 text-sm transition-colors",
                active
                  ? "bg-zinc-800 text-zinc-50"
                  : "text-zinc-400 hover:bg-zinc-900 hover:text-zinc-100",
              )}
            >
              <Icon className="size-4" />
              {item.label}
            </Link>
          );
        })}
      </nav>
      <div className="border-t border-zinc-800 p-3 text-xs text-zinc-500">
        {planHint}
      </div>
    </aside>
  );
}
