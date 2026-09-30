// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import { handleSync } from "./처리.ts";

Deno.serve((request) => {
  let services;
  try {
    const config = readCloudConfig((name) => Deno.env.get(name));
    services = createCloudServices(config, createClient);
  } catch {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 503,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }

  return handleSync(request, {
    authenticate: async (incoming) => (await services.authenticate(incoming))?.userId ?? null,
    submit: async (userId, events) => {
      const inserted = await services.rpc("sync_submit", { p_user_id: userId, p_events: events });
      if (typeof inserted !== "number") throw new Error("sync_result_invalid");
      return inserted;
    },
  });
});
