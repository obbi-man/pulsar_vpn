"use client";

import { useState } from "react";
import { Loader2, Server } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Progress } from "@/components/ui/progress";
import { cn } from "@/lib/utils";

type StepKey = "idle" | "ssh" | "docker" | "protocol" | "done" | "error";

const steps: { key: StepKey; label: string }[] = [
  { key: "ssh", label: "1. Проверка SSH" },
  { key: "docker", label: "2. Установка Docker" },
  { key: "protocol", label: "3. Pulsar" },
];

function stepIndex(step: StepKey): number {
  if (step === "idle") return 0;
  if (step === "ssh") return 1;
  if (step === "docker") return 2;
  if (step === "protocol" || step === "done") return 3;
  return 0;
}

export default function ServerPage() {
  const [ip, setIp] = useState("");
  const [login, setLogin] = useState("root");
  const [password, setPassword] = useState("");
  const [port, setPort] = useState("22");
  const [step, setStep] = useState<StepKey>("idle");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    setLoading(true);
    setStep("ssh");

    const progressTimer = window.setTimeout(() => setStep("docker"), 900);
    const progressTimer2 = window.setTimeout(() => setStep("protocol"), 1800);

    try {
      const res = await fetch("/api/server/setup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          ip,
          login,
          password,
          port: Number(port) || 22,
        }),
      });

      const data = (await res.json()) as {
        ok?: boolean;
        message?: string;
        error?: string;
        details?: string;
        server?: { id: string; host: string };
      };

      window.clearTimeout(progressTimer);
      window.clearTimeout(progressTimer2);

      if (!res.ok) {
        setStep("error");
        setError(
          [data.error, data.details].filter(Boolean).join(" — ") ||
            "Ошибка настройки сервера",
        );
        return;
      }

      setStep("done");
      setSuccess(
        data.message ??
          `Сервер ${data.server?.host ?? ip} успешно подключён (${data.server?.id ?? ""})`,
      );
    } catch (err) {
      window.clearTimeout(progressTimer);
      window.clearTimeout(progressTimer2);
      setStep("error");
      setError(err instanceof Error ? err.message : "Сетевая ошибка");
    } finally {
      setLoading(false);
    }
  }

  const progressValue = (stepIndex(step) / 3) * 100;

  return (
    <div className="mx-auto max-w-2xl space-y-8">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-semibold tracking-tight text-zinc-50">
          <Server className="size-6" />
          Сервер
        </h1>
        <p className="mt-1 text-sm text-zinc-400">
          Укажите данные VPS (Ubuntu 22.04). Панель сама установит Docker и
          Pulsar.
        </p>
      </div>

      <form
        onSubmit={onSubmit}
        className="space-y-5 rounded-lg border border-zinc-800 bg-zinc-900/40 p-6"
      >
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="ip">IP-адрес VPS</Label>
            <Input
              id="ip"
              placeholder="203.0.113.10"
              value={ip}
              onChange={(e) => setIp(e.target.value)}
              required
              className="border-zinc-700 bg-zinc-950"
              autoComplete="off"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="login">Логин</Label>
            <Input
              id="login"
              placeholder="root"
              value={login}
              onChange={(e) => setLogin(e.target.value)}
              required
              className="border-zinc-700 bg-zinc-950"
              autoComplete="username"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="port">SSH порт</Label>
            <Input
              id="port"
              type="number"
              placeholder="22"
              value={port}
              onChange={(e) => setPort(e.target.value)}
              className="border-zinc-700 bg-zinc-950"
            />
          </div>
          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="password">Пароль</Label>
            <Input
              id="password"
              type="password"
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="border-zinc-700 bg-zinc-950"
              autoComplete="current-password"
            />
          </div>
        </div>

        <Button
          type="submit"
          disabled={loading}
          className="w-full bg-zinc-100 text-zinc-950 hover:bg-white"
        >
          {loading ? (
            <>
              <Loader2 className="size-4 animate-spin" />
              Подключение…
            </>
          ) : (
            "Подключить сервер"
          )}
        </Button>

        {step !== "idle" && (
          <div className="space-y-3 pt-2">
            <Progress value={progressValue} className="h-1.5 bg-zinc-800" />
            <ol className="space-y-2">
              {steps.map((s) => {
                const current = stepIndex(step);
                const mine = stepIndex(s.key);
                const done = current > mine || step === "done";
                const active = step === s.key || (step === "protocol" && s.key === "protocol");
                return (
                  <li
                    key={s.key}
                    className={cn(
                      "flex items-center gap-2 text-sm",
                      done
                        ? "text-emerald-400"
                        : active
                          ? "text-zinc-100"
                          : "text-zinc-500",
                    )}
                  >
                    <span
                      className={cn(
                        "inline-flex size-5 items-center justify-center rounded-full border text-[10px]",
                        done
                          ? "border-emerald-500/50 bg-emerald-500/10"
                          : active
                            ? "border-zinc-500 bg-zinc-800"
                            : "border-zinc-800",
                      )}
                    >
                      {done ? "✓" : mine}
                    </span>
                    {s.label}
                    {active && loading && (
                      <Loader2 className="size-3 animate-spin text-zinc-400" />
                    )}
                  </li>
                );
              })}
            </ol>
          </div>
        )}

        {error && (
          <p className="rounded-md border border-red-900/50 bg-red-950/40 px-3 py-2 text-sm text-red-300">
            {error}
          </p>
        )}
        {success && (
          <p className="rounded-md border border-emerald-900/50 bg-emerald-950/40 px-3 py-2 text-sm text-emerald-300">
            {success}
          </p>
        )}
      </form>

      <div className="rounded-lg border border-dashed border-zinc-800 bg-zinc-900/20 p-4 text-sm text-zinc-400">
        <p className="font-medium text-zinc-200">Подсказка для новичков</p>
        <p className="mt-1 leading-relaxed">
          Купите VPS на Ubuntu 22.04 у любого провайдера (например, Hetzner,
          DigitalOcean, Timeweb или Aeza). После оплаты вам пришлют IP, логин
          root и пароль — вставьте их в форму выше. Панель сама проверит SSH,
          поставит Docker и поднимет Pulsar.
        </p>
      </div>
    </div>
  );
}
