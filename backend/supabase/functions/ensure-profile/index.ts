// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import { handleEnsureProfile, type Profile } from "./처리.ts";

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

  return handleEnsureProfile(request, {
    authenticate: services.authenticate,
    ensure: async (userId, isGuest) => {
      const data = await services.rpc("ensure_profile", { p_user_id: userId, p_is_guest: isGuest });
      if (!data || typeof data !== "object" || Array.isArray(data) ||
          (data as Record<string, unknown>).user_id !== userId) {
        throw new Error("profile_result_invalid");
      }
      return data as Profile;
    },
  });
});
