import { Suspense } from "react";

import { LoginForm } from "@/components/auth/login-form";

export default function LoginPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-zinc-950 text-zinc-400">
          Загрузка…
        </div>
      }
    >
      <LoginForm />
    </Suspense>
  );
}
