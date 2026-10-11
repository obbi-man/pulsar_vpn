export type ServerStatus = "pending" | "active" | "error";
export type Plan = "free" | "pro";

export type ServerRow = {
  id: string;
  admin_id: string;
  name: string;
  ip_address: string;
  ssh_port: number;
  vpn_port: number;
  secret_key: string;
  status: ServerStatus;
  created_at: string;
};

export type VpnUserRow = {
  id: string;
  server_id: string;
  admin_id: string;
  name: string;
  connection_id: string;
  is_active: boolean;
  created_at: string;
};

export type ProfileRow = {
  id: string;
  plan: Plan;
  plan_expires_at: string | null;
  stripe_customer_id: string | null;
  updated_at: string;
};

export type Database = {
  public: {
    Tables: {
      servers: {
        Row: ServerRow;
        Insert: {
          id?: string;
          admin_id: string;
          name?: string;
          ip_address: string;
          ssh_port?: number;
          vpn_port?: number;
          secret_key: string;
          status?: ServerStatus;
          created_at?: string;
        };
        Update: Partial<ServerRow>;
        Relationships: [];
      };
      vpn_users: {
        Row: VpnUserRow;
        Insert: {
          id?: string;
          server_id: string;
          admin_id: string;
          name: string;
          connection_id: string;
          is_active?: boolean;
          created_at?: string;
        };
        Update: Partial<VpnUserRow>;
        Relationships: [];
      };
      profiles: {
        Row: ProfileRow;
        Insert: {
          id: string;
          plan?: Plan;
          plan_expires_at?: string | null;
          stripe_customer_id?: string | null;
          updated_at?: string;
        };
        Update: Partial<ProfileRow>;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};

export const FREE_USER_LIMIT = 20;

/** Access URL for Flutter client — pulsar:// preferred; cs:// still accepted. */
export function buildAccessUrl(input: {
  secretKey: string;
  serverIp: string;
  vpnPort: number;
  connectionId: string;
  /** @default "pulsar" */
  scheme?: "pulsar" | "cs";
}): string {
  const secret = encodeURIComponent(input.secretKey);
  const id = encodeURIComponent(input.connectionId);
  const scheme = input.scheme ?? "pulsar";
  return `${scheme}://${secret}@${input.serverIp}:${input.vpnPort}/?id=${id}`;
}

/** Random 4-byte hex connection id (8 lowercase hex chars). */
export function randomConnectionId(): string {
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
