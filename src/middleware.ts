import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import {
  DEMO_COOKIE,
  demoCookieValue,
  isLocalDemoEnabled,
} from "@/lib/local-demo";

export async function middleware(request: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const path = request.nextUrl.pathname;
  const demoOn = isLocalDemoEnabled();
  const hasDemo =
    demoOn && request.cookies.get(DEMO_COOKIE)?.value === demoCookieValue();

  let response = NextResponse.next({
    request: { headers: request.headers },
  });

  // Local demo: cookie session, no Supabase required.
  if (demoOn && (!url || !anonKey)) {
    const isDashboard = path.startsWith("/dashboard");
    const isLogin = path.startsWith("/login");
    const isAuthApi = path.startsWith("/api/auth");
    const isApi =
      path.startsWith("/api/") &&
      !isAuthApi &&
      request.method !== "OPTIONS";

    if (isDashboard && !hasDemo) {
      const login = request.nextUrl.clone();
      login.pathname = "/login";
      login.searchParams.set("next", path);
      return NextResponse.redirect(login);
    }
    if (isLogin && hasDemo) {
      const next =
        request.nextUrl.searchParams.get("next") || "/dashboard/server";
      return NextResponse.redirect(new URL(next, request.url));
    }
    if (isApi && !hasDemo) {
      return NextResponse.json(
        { error: "Требуется авторизация", code: "AUTH_ERROR" },
        { status: 401 },
      );
    }
    return response;
  }

  if (!url || !anonKey) {
    if (path.startsWith("/dashboard")) {
      const login = request.nextUrl.clone();
      login.pathname = "/login";
      login.searchParams.set("next", path);
      return NextResponse.redirect(login);
    }
    return response;
  }

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({
          request: { headers: request.headers },
        });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const authed = Boolean(user) || hasDemo;
  const isDashboard = path.startsWith("/dashboard");
  const isLogin = path.startsWith("/login");
  const isAuthApi = path.startsWith("/api/auth");

  if (isDashboard && !authed) {
    const login = request.nextUrl.clone();
    login.pathname = "/login";
    login.searchParams.set("next", path);
    return NextResponse.redirect(login);
  }

  if (isLogin && authed) {
    const next = request.nextUrl.searchParams.get("next") || "/dashboard/server";
    return NextResponse.redirect(new URL(next, request.url));
  }

  if (
    path.startsWith("/api/") &&
    !isAuthApi &&
    !authed &&
    request.method !== "OPTIONS"
  ) {
    return NextResponse.json(
      { error: "Требуется авторизация", code: "AUTH_ERROR" },
      { status: 401 },
    );
  }

  return response;
}

export const config = {
  matcher: [
    "/dashboard/:path*",
    "/login",
    "/api/server/:path*",
    "/api/users/:path*",
    "/api/servers/:path*",
    "/api/billing/:path*",
  ],
};
