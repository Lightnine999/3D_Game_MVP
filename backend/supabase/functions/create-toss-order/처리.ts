import { priceFor, type Order } from "../_shared/결제.ts";

export type OrderDependencies = {
  authenticate(request: Request): Promise<string | null> | string | null;
  insert(order: Order): Promise<Order> | Order;
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleCreateOrder(request: Request, dependencies: OrderDependencies): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const userId = await dependencies.authenticate(request);
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
    if ("amount" in input) return json(400, { error: "client_amount_forbidden" });
    const product = typeof input.product_id === "string" ? priceFor(input.product_id) : null;
    if (!product) return json(400, { error: "unknown_product" });

    const order: Order = {
      order_id: crypto.randomUUID(),
      user_id: userId,
      product_id: product.product_id,
      amount: product.amount,
      status: "ready",
    };
    const stored = await dependencies.insert(order);
    if (stored.order_id !== order.order_id || stored.user_id !== userId ||
        stored.product_id !== product.product_id ||
        stored.amount !== product.amount || stored.status !== "ready") {
      return json(500, { error: "internal_error" });
    }
    return json(201, {
      orderId: stored.order_id,
      productId: product.product_id,
      amount: stored.amount,
      orderName: product.name,
      status: stored.status,
    });
  } catch {
    return json(500, { error: "internal_error" });
  }
}
