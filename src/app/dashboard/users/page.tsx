"use client";

import { useCallback, useEffect, useState } from "react";
import { Check, Copy, Loader2, Plus, Users } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type VpnUser = {
  id: string;
  name: string;
  connection_id: string;
  access_url: string;
  is_active: boolean;
  status: "active" | "disabled";
  created_at: string;
};

type ServerInfo = {
  id: string;
  name: string;
  ip_address: string;
  vpn_port: number;
};

function formatDate(iso: string): string {
  try {
    return new Intl.DateTimeFormat("ru-RU", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export default function UsersPage() {
  const [users, setUsers] = useState<VpnUser[]>([]);
  const [server, setServer] = useState<ServerInfo | null>(null);
  const [used, setUsed] = useState(0);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [createOpen, setCreateOpen] = useState(false);
  const [limitOpen, setLimitOpen] = useState(false);
  const [createdUrl, setCreatedUrl] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [limit, setLimit] = useState<number | null>(20);
  const [plan, setPlan] = useState<"free" | "pro">("free");

  const atLimit = limit != null && used >= limit;

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/users");
      const data = (await res.json()) as {
        users?: VpnUser[];
        used?: number;
        limit?: number | null;
        plan?: "free" | "pro";
        server?: ServerInfo | null;
        error?: string;
        message?: string;
      };
      if (res.status === 401) {
        window.location.href = "/login?next=/dashboard/users";
        return;
      }
      if (!res.ok) {
        setError(data.error ?? "Не удалось загрузить пользователей");
        return;
      }
      setUsers(data.users ?? []);
      setUsed(data.used ?? data.users?.length ?? 0);
      setLimit(data.limit === undefined ? 20 : data.limit);
      setPlan(data.plan ?? "free");
      setServer(data.server ?? null);
      if (data.message && !(data.users?.length)) {
        setError(data.message);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Сетевая ошибка");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  function onClickCreate() {
    if (!server) {
      setError("Сначала подключите сервер на вкладке «Сервер»");
      return;
    }
    if (atLimit) {
      setLimitOpen(true);
      return;
    }
    setName("");
    setCreatedUrl(null);
    setCreateOpen(true);
  }

  async function onCreate(e: React.FormEvent) {
    e.preventDefault();
    if (atLimit) {
      setCreateOpen(false);
      setLimitOpen(true);
      return;
    }
    setCreating(true);
    setError(null);
    try {
      const res = await fetch("/api/users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          serverId: server?.id,
        }),
      });
      const data = (await res.json()) as {
        user?: VpnUser;
        access_url?: string;
        error?: string;
        limitReached?: boolean;
      };
      if (res.status === 403 || data.limitReached) {
        setCreateOpen(false);
        setLimitOpen(true);
        await load();
        return;
      }
      if (!res.ok) {
        setError(data.error ?? "Не удалось создать пользователя");
        return;
      }
      setCreatedUrl(data.access_url ?? data.user?.access_url ?? null);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Сетевая ошибка");
    } finally {
      setCreating(false);
    }
  }

  async function copyUrl(url: string) {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      setError("Не удалось скопировать ключ");
    }
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold tracking-tight text-zinc-50">
            <Users className="size-6" />
            Пользователи
          </h1>
          <p className="mt-1 text-sm text-zinc-400">
            Тариф {plan === "pro" ? "Pro" : "Free"} · использовано {used}
            {limit != null ? ` из ${limit}` : " (безлимит)"}
            {server ? ` · ${server.ip_address}:${server.vpn_port}` : ""}
          </p>
        </div>
        <Button
          onClick={onClickCreate}
          disabled={!server || loading}
          className="bg-zinc-100 text-zinc-950 hover:bg-white disabled:opacity-40"
        >
          <Plus className="size-4" />
          Создать пользователя
        </Button>
      </div>

      {error && (
        <p className="rounded-md border border-amber-900/40 bg-amber-950/30 px-3 py-2 text-sm text-amber-200">
          {error}
        </p>
      )}

      <div className="overflow-hidden rounded-lg border border-zinc-800">
        <Table>
          <TableHeader>
            <TableRow className="border-zinc-800 hover:bg-transparent">
              <TableHead className="text-zinc-400">Имя</TableHead>
              <TableHead className="text-zinc-400">Connection ID</TableHead>
              <TableHead className="text-zinc-400">Дата создания</TableHead>
              <TableHead className="text-zinc-400">Ключ cs://</TableHead>
              <TableHead className="text-zinc-400">Статус</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {loading ? (
              <TableRow className="border-zinc-800">
                <TableCell colSpan={5} className="py-10 text-center text-zinc-500">
                  <Loader2 className="mx-auto size-5 animate-spin" />
                </TableCell>
              </TableRow>
            ) : users.length === 0 ? (
              <TableRow className="border-zinc-800">
                <TableCell colSpan={5} className="py-10 text-center text-zinc-500">
                  Пока нет пользователей. Создайте первого клиента VPN.
                </TableCell>
              </TableRow>
            ) : (
              users.map((u) => (
                <TableRow key={u.id} className="border-zinc-800">
                  <TableCell className="font-medium text-zinc-100">
                    {u.name}
                  </TableCell>
                  <TableCell className="font-mono text-xs text-zinc-400">
                    {u.connection_id}
                  </TableCell>
                  <TableCell className="text-zinc-400">
                    {formatDate(u.created_at)}
                  </TableCell>
                  <TableCell className="max-w-[220px]">
                    <button
                      type="button"
                      onClick={() => void copyUrl(u.access_url)}
                      className="inline-flex max-w-full items-center gap-1 truncate font-mono text-xs text-zinc-300 hover:text-white"
                      title={u.access_url}
                    >
                      <Copy className="size-3 shrink-0" />
                      <span className="truncate">{u.access_url}</span>
                    </button>
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant="secondary"
                      className={
                        u.is_active
                          ? "bg-emerald-500/15 text-emerald-300"
                          : "bg-zinc-800 text-zinc-400"
                      }
                    >
                      {u.is_active ? "Активен" : "Отключён"}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>

      <Dialog
        open={createOpen}
        onOpenChange={(open) => {
          setCreateOpen(open);
          if (!open) setCreatedUrl(null);
        }}
      >
        <DialogContent className="border-zinc-800 bg-zinc-950 text-zinc-100 sm:max-w-md">
          {createdUrl ? (
            <>
              <DialogHeader>
                <DialogTitle>Пользователь создан</DialogTitle>
                <DialogDescription className="text-zinc-400">
                  Скопируйте ключ доступа и вставьте его в приложение Pulsar.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3 py-2">
                <code className="block break-all rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-xs text-zinc-200">
                  {createdUrl}
                </code>
                <Button
                  className="w-full bg-zinc-100 text-zinc-950 hover:bg-white"
                  onClick={() => void copyUrl(createdUrl)}
                >
                  {copied ? (
                    <>
                      <Check className="size-4" /> Скопировано
                    </>
                  ) : (
                    <>
                      <Copy className="size-4" /> Копировать cs://
                    </>
                  )}
                </Button>
              </div>
              <DialogFooter>
                <Button
                  variant="outline"
                  className="border-zinc-700"
                  onClick={() => setCreateOpen(false)}
                >
                  Закрыть
                </Button>
              </DialogFooter>
            </>
          ) : (
            <form onSubmit={onCreate}>
              <DialogHeader>
                <DialogTitle>Новый пользователь</DialogTitle>
                <DialogDescription className="text-zinc-400">
                  Будет создан уникальный Connection ID и ключ{" "}
                  <span className="font-mono text-zinc-300">
                    cs://&lt;secret&gt;@&lt;ip&gt;:&lt;port&gt;/?id=…
                  </span>
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-2 py-4">
                <Label htmlFor="name">Имя</Label>
                <Input
                  id="name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Например, Иван"
                  required
                  className="border-zinc-700 bg-zinc-900"
                />
              </div>
              <DialogFooter>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setCreateOpen(false)}
                  className="border-zinc-700"
                >
                  Отмена
                </Button>
                <Button
                  type="submit"
                  disabled={creating || atLimit}
                  className="bg-zinc-100 text-zinc-950 hover:bg-white"
                >
                  {creating ? (
                    <Loader2 className="size-4 animate-spin" />
                  ) : (
                    "Создать"
                  )}
                </Button>
              </DialogFooter>
            </form>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={limitOpen} onOpenChange={setLimitOpen}>
        <DialogContent className="border-zinc-800 bg-zinc-950 text-zinc-100 sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Лимит бесплатного тарифа</DialogTitle>
            <DialogDescription className="text-zinc-400">
              Достигнут лимит Free ({limit ?? 20} пользователей). Чтобы добавить
              больше клиентов, перейдите на тариф Pro.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setLimitOpen(false)}
              className="border-zinc-700"
            >
              Закрыть
            </Button>
            <Button
              className="bg-zinc-100 text-zinc-950 hover:bg-white"
              onClick={() => {
                setLimitOpen(false);
                window.location.href = "/dashboard/pricing";
              }}
            >
              Перейти на Pro
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
