// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { readCloudConfig } from "../_shared/클라우드.ts";
import { createCloudServices } from "../_shared/클라우드_연결.ts";
import { confirmPaymentWithToss } from "../_shared/토스.ts";
import type { Order } from "../_shared/결제.ts";
import { handleConfirmPayment } from "./처리.ts";

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

  return handleConfirmPayment(request, {
    authenticate: async (incoming) => (await services.authenticate(incoming))?.userId ?? null,
    findOrder: async (orderId) => {
      const result = await admin.from("toss_orders")
        .select("order_id,user_id,product_id,amount,status").eq("order_id", orderId).maybeSingle();
      if (result.error) throw new Error("order_read_failed");
      if (!result.data) return null;
      if (result.data.status !== "paid") return result.data as Order;
      const purchase = await admin.from("purchases").select("payment_key")
        .eq("order_id", orderId).maybeSingle();
      if (purchase.error || !purchase.data) throw new Error("paid_record_missing");
      return { ...result.data, payment_key: purchase.data.payment_key } as Order;
    },
    requestApproval: (attempt) => confirmPaymentWithToss(Deno.env.get("TOSS_TEST_SECRET_KEY") || "", attempt),
    grant: async (order, approval) => {
      const result = await services.rpc("finalize_payment", {
        p_order_id: order.order_id, p_user_id: order.user_id,
        p_payment_key: approval.paymentKey, p_amount: order.amount,
      });
      if (result !== "paid" && result !== "already_paid") throw new Error("grant_failed");
      return result;
    },
  });
});
