// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import type { Order } from "../_shared/결제.ts";
import { handleCreateOrder } from "./처리.ts";

Deno.serve((request) => {
  let services;
  try {
    services = createCloudServices(readCloudConfig((name) => Deno.env.get(name)), createClient);
  } catch {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 503, headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  return handleCreateOrder(request, {
    authenticate: async (incoming) => (await services.authenticate(incoming))?.userId ?? null,
    insert: async (order) => {
      const data = await services.rpc("create_order", {
        p_user_id: order.user_id, p_order_id: order.order_id,
        p_product_id: order.product_id, p_amount: order.amount,
      });
      if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("order_create_failed");
      return data as Order;
    },
  });
});
