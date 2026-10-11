"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { LogOut, User } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export function DashboardTopbar() {
  const router = useRouter();
  const [email, setEmail] = useState<string>("…");

  useEffect(() => {
    setEmail("admin@pulsar.local");
    try {
      const supabase = createSupabaseBrowserClient();
      void supabase.auth.getUser().then(({ data }) => {
        if (data.user?.email) setEmail(data.user.email);
      });
    } catch {
      // local demo — keep demo email
    }
  }, []);

  async function logout() {
    try {
      await fetch("/api/auth/logout", { method: "POST" });
      try {
        const supabase = createSupabaseBrowserClient();
        await supabase.auth.signOut();
      } catch {
        // local demo has no Supabase client
      }
    } catch {
      // ignore
    }
    router.replace("/login");
    router.refresh();
  }

  return (
    <header className="flex h-14 items-center justify-between border-b border-zinc-800 bg-zinc-950/80 px-6 backdrop-blur">
      <div>
        <p className="text-sm font-medium text-zinc-100">Панель администратора</p>
        <p className="text-xs text-zinc-500">Управление VPS и VPN-пользователями</p>
      </div>
      <div className="flex items-center gap-3">
        <Badge variant="secondary" className="bg-zinc-800 text-zinc-300">
          Free
        </Badge>
        <div className="flex items-center gap-2 rounded-md border border-zinc-800 bg-zinc-900 px-3 py-1.5">
          <User className="size-4 text-zinc-400" />
          <div className="leading-tight">
            <p className="text-xs font-medium text-zinc-100">Админ</p>
            <p className="max-w-[160px] truncate text-[11px] text-zinc-500">
              {email}
            </p>
          </div>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => void logout()}
          className="border-zinc-700 text-zinc-300"
        >
          <LogOut className="size-3.5" />
          Выйти
        </Button>
      </div>
    </header>
  );
}
