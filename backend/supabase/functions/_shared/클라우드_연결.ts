import { verifiedAccount, type AuthUser, type VerifiedAccount } from "./인증.ts";
import type { CloudConfig } from "./클라우드.ts";

type AuthResult = { data: { user: AuthUser | null }; error: unknown };
type RpcResult = { data: unknown; error: unknown };

type CloudClient = {
  auth: { getUser(token: string): PromiseLike<AuthResult> };
  rpc(name: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
};

export type ClientFactory = (url: string, key: string) => CloudClient;

export function createCloudServices(config: CloudConfig, createClient: ClientFactory): {
  authenticate(request: Request): Promise<VerifiedAccount | null>;
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
} {
  const publicClient = createClient(config.url, config.publicKey);
  const adminClient = createClient(config.url, config.serviceKey);

  return {
    authenticate: (request) => verifiedAccount(request, async (token) => {
      const { data, error } = await publicClient.auth.getUser(token);
      return error ? null : data.user;
    }),
    rpc: async (name, args) => {
      const { data, error } = await adminClient.rpc(name, args);
      if (error) throw new Error("db_failed");
      return data;
    },
  };
}
