// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import { handleAdminOverview } from "./처리.ts";

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
  return handleAdminOverview(request, {
    authenticate: async (incoming) => (await services.authenticate(incoming))?.userId ?? null,
    isAdmin: async (userId) => {
      const { data, error } = await admin.from("profiles").select("role").eq("id", userId).maybeSingle();
      if (error) throw new Error("role_check_failed");
      return data?.role === "admin";
    },
    list: async (view) => {
      const { data, error } = await admin.from(view).select("*").limit(100);
      if (error || !data) throw new Error("admin_view_failed");
      return data;
    },
  });
});
