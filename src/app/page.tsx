import { Shield } from "lucide-react";

/**
 * API-only backend landing — the product is the Pulsar native app, not this site.
 */
export default function HomePage() {
  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden bg-zinc-950 px-6 text-zinc-100">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,_rgba(113,113,122,0.18),_transparent_55%),radial-gradient(ellipse_at_bottom,_rgba(24,24,27,0.9),_#09090b)]"
      />
      <div className="relative z-10 mx-auto max-w-lg text-center">
        <div className="mb-5 inline-flex items-center gap-2 text-zinc-100">
          <Shield className="size-7" />
          <span className="text-2xl font-semibold tracking-tight">
            Pulsar VPN
          </span>
        </div>
        <p className="text-sm leading-relaxed text-zinc-400">
          Это API-бэкенд конструктора (ваш VPS). Продукт — нативное приложение
          Pulsar для телефона и ПК, не веб-панель.
        </p>
        <p className="mt-4 text-xs text-zinc-600">
          Endpoints: /api/auth/* · /api/server/setup · /api/users · /api/billing/*
        </p>
      </div>
    </div>
  );
}
