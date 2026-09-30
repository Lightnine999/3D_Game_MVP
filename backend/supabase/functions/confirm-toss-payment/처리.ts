import { confirmOnce, type ApprovalDependencies, type ConfirmationRequest, type Order } from "../_shared/결제.ts";

export type ConfirmDependencies = ApprovalDependencies & {
  authenticate(request: Request): Promise<string | null> | string | null;
  findOrder(orderId: string): Promise<Order | null> | Order | null;
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleConfirmPayment(request: Request, deps: ConfirmDependencies): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const userId = await deps.authenticate(request);
    if (!userId) return json(401, { error: "unauthorized" });

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "invalid_json" });
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json(400, { error: "invalid_json" });
    }
    const input = body as Record<string, unknown>;
    if (typeof input.paymentKey !== "string" || !input.paymentKey ||
        typeof input.orderId !== "string" || !input.orderId ||
        typeof input.amount !== "number" || !Number.isSafeInteger(input.amount) || input.amount <= 0) {
      return json(400, { error: "invalid_confirmation_request" });
    }
    const confirmation = input as ConfirmationRequest;
    const order = await deps.findOrder(confirmation.orderId);
    if (!order || order.user_id !== userId) return json(404, { error: "order_not_found" });

    const result = await confirmOnce(order, userId, confirmation, deps);
    if (result === "paid" || result === "already_paid") {
      return json(200, { status: result, orderId: confirmation.orderId });
    }
    if (result === "already_paid_conflict" || result === "invalid_status") {
      return json(409, { error: result });
    }
    if (result === "amount_mismatch" || result === "invalid_request") {
      return json(400, { error: result });
    }
    if (result === "provider_mismatch") return json(502, { error: result });
    return json(500, { error: "internal_error" });
  } catch (error) {
    const code = error instanceof Error ? error.message : "";
    if (code === "test_secret_required") return json(503, { error: "test_key_missing" });
    if (code === "toss_confirmation_rejected" || code === "invalid_toss_response") {
      return json(502, { error: "toss_confirmation_failed" });
    }
    return json(500, { error: "internal_error" });
  }
}
