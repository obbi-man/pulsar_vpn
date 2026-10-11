"use client";

import { FormEvent, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Loader2, Shield } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

const DEMO_EMAIL = "admin@pulsar.local";
const DEMO_PASSWORD = "demo-admin";

export function LoginForm() {
  const router = useRouter();
  const search = useSearchParams();
  const next = search.get("next") || "/dashboard/server";

  const [email, setEmail] = useState(DEMO_EMAIL);
  const [password, setPassword] = useState(DEMO_PASSWORD);
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function tryDemoLogin(): Promise<boolean> {
    const res = await fetch("/api/auth/demo-login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    return res.ok;
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      // Prefer local demo when enabled (no Supabase needed).
      if (mode === "login" && (await tryDemoLogin())) {
        router.replace(next);
        router.refresh();
        return;
      }

      const supabase = createSupabaseBrowserClient();
      if (mode === "login") {
        const { error: err } = await supabase.auth.signInWithPassword({
          email,
          password,
        });
        if (err) throw err;
      } else {
        const { error: err } = await supabase.auth.signUp({ email, password });
        if (err) throw err;
      }
      router.replace(next);
      router.refresh();
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Ошибка входа. Демо: admin@pulsar.local / demo-admin (CS_LOCAL_DEMO=1).",
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-zinc-950 px-4 text-zinc-100">
      <div className="w-full max-w-md space-y-6 rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
        <div className="text-center">
          <div className="mb-3 inline-flex items-center gap-2 text-zinc-50">
            <Shield className="size-6" />
            <span className="text-xl font-semibold">Pulsar VPN</span>
          </div>
          <p className="text-sm text-zinc-400">
            API-вход (продукт — нативное приложение Pulsar)
          </p>
        </div>

        <form onSubmit={onSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="border-zinc-700 bg-zinc-950"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Пароль</Label>
            <Input
              id="password"
              type="password"
              required
              minLength={6}
              autoComplete={
                mode === "login" ? "current-password" : "new-password"
              }
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="border-zinc-700 bg-zinc-950"
            />
          </div>

          {error && (
            <p className="rounded-md border border-red-900/50 bg-red-950/40 px-3 py-2 text-sm text-red-300">
              {error}
            </p>
          )}

          <Button
            type="submit"
            disabled={loading}
            className="w-full bg-zinc-100 text-zinc-950 hover:bg-white"
          >
            {loading ? (
              <Loader2 className="size-4 animate-spin" />
            ) : mode === "login" ? (
              "Войти"
            ) : (
              "Создать аккаунт"
            )}
          </Button>
        </form>

        <p className="rounded-md border border-zinc-800 bg-zinc-950/60 px-3 py-2 text-xs text-zinc-500">
          Локальный демо:{" "}
          <code className="text-zinc-300">{DEMO_EMAIL}</code> /{" "}
          <code className="text-zinc-300">{DEMO_PASSWORD}</code>
          {" "}(при <code className="text-zinc-400">CS_LOCAL_DEMO=1</code>)
        </p>

        <button
          type="button"
          className="w-full text-center text-sm text-zinc-400 hover:text-zinc-200"
          onClick={() => setMode((m) => (m === "login" ? "signup" : "login"))}
        >
          {mode === "login"
            ? "Нет аккаунта? Зарегистрироваться"
            : "Уже есть аккаунт? Войти"}
        </button>
      </div>
    </div>
  );
}
