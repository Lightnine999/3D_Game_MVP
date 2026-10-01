// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import { askModel, type ModelTurn } from "../_shared/모델.ts";
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
    create: async (userId, input, requestId) => {
      const result = await services.rpc("create_support_request", {
        p_user_id: userId, p_kind: input.kind, p_message: input.message, p_context: input.bugContext, p_request_id: requestId,
      });
      if (result === "daily_limit_reached") throw new Error("daily_limit_reached");
      if (typeof result !== "string" || !result) throw new Error("support_store_failed");
      return result;
    },
    append: async (userId, threadId, message, requestId) => {
      const result = await services.rpc("append_support_message", {
        p_user_id: userId, p_thread_id: threadId, p_message: message, p_request_id: requestId,
      });
      if (result === "daily_limit_reached") throw new Error("daily_limit_reached");
      if (result === "thread_busy") throw new Error("thread_busy");
      return result === threadId ? threadId : null;
    },
    history: async (userId, threadId, requestId) => {
      const rows = await services.rpc("support_history", { p_user_id: userId, p_thread_id: threadId, p_request_id: requestId });
      if (rows === "support_request_expired") throw new Error("support_request_expired");
      if (!Array.isArray(rows)) throw new Error("invalid_support_history");
      return rows.filter((row): row is ModelTurn => row && typeof row === "object" &&
        (row.role === "user" || row.role === "assistant") && typeof row.content === "string" &&
        row.content.length <= 2000).slice(-8);
    },
    release: async (userId, threadId, requestId) => {
      await services.rpc("release_support_request", {
        p_user_id: userId, p_thread_id: threadId, p_request_id: requestId,
      });
    },
    answer: (message, history) => askModel(Deno.env.get("OPENAI_API_KEY") || "", Deno.env.get("OPENAI_MODEL") || "", history ?? message),
    finish: async (userId, threadId, status, reply, requestId) => {
      const result = await services.rpc("finish_support_request", {
        p_user_id: userId, p_thread_id: threadId, p_status: status, p_reply: reply, p_request_id: requestId,
      });
      if (result === "support_request_expired") throw new Error("support_request_expired");
      if (result !== "ok") throw new Error("support_finish_failed");
    },
  });
});
