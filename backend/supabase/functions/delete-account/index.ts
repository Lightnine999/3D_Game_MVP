// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import { handleDeleteAccount } from "./처리.ts";

Deno.serve((request) => {
  let services;
  let admin;
  try {
    const config = readCloudConfig((name) => Deno.env.get(name));
    services = createCloudServices(config, createClient);
    admin = createClient(config.url, config.serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  } catch {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 503, headers: { "content-type": "application/json; charset=utf-8" },
    });
  }

  return handleDeleteAccount(request, {
    authenticate: async (incoming) => (await services.authenticate(incoming))?.userId ?? null,
    deleteUser: async (userId) => {
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) throw new Error("account_delete_failed");
    },
  });
});
