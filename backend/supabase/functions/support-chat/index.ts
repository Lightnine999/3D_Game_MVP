// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import { askModel } from "../_shared/모델.ts";
import { handleSupport } from "./처리.ts";

Deno.serve((request) => {
  let services;
  try {
    services = createCloudServices(readCloudConfig((name) => Deno.env.get(name)), createClient);
  } catch {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 503, headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  return handleSupport(request, {
    authenticate: async (incoming) => (await services.authenticate(incoming))?.userId ?? null,
    canAnswer: () => Boolean(Deno.env.get("OPENAI_API_KEY") && Deno.env.get("OPENAI_MODEL")),
    create: async (userId, input) => {
      const result = await services.rpc("create_support_request", {
        p_user_id: userId, p_kind: input.kind, p_message: input.message, p_context: input.bugContext,
      });
      if (result === "daily_limit_reached") throw new Error("daily_limit_reached");
      if (typeof result !== "string" || !result) throw new Error("support_store_failed");
      return result;
    },
    answer: (message) => askModel(Deno.env.get("OPENAI_API_KEY") || "", Deno.env.get("OPENAI_MODEL") || "", message),
    finish: async (userId, threadId, status, reply) => {
      const result = await services.rpc("finish_support_request", {
        p_user_id: userId, p_thread_id: threadId, p_status: status, p_reply: reply,
      });
      if (result !== "ok") throw new Error("support_finish_failed");
    },
  });
});
