export type Order = {
  order_id: string;
  user_id: string;
  product_id: string;
  amount: number;
  status: "ready" | "paid" | "failed";
  payment_key?: string | null;
};

export type ConfirmationRequest = {
  paymentKey: string;
  orderId: string;
  amount: number;
};

export type ApprovalResponse = {
  paymentKey: string;
  orderId: string;
  totalAmount: number;
  status: string;
};

export type ApprovalDependencies = {
  requestApproval(request: ConfirmationRequest): Promise<ApprovalResponse>;
  grant(order: Order, approval: ApprovalResponse): Promise<"paid" | "already_paid">;
};

const PRODUCTS: Readonly<Record<string, { item_id: string; amount: number; name: string }>> = {
  ammo_start_pack: { item_id: "ammo_start_pack", amount: 1100, name: "시작 탄약 팩" },
  supporter_badge: { item_id: "supporter_badge", amount: 3300, name: "서포터 배지" },
};

export function priceFor(productId: string): { item_id: string; amount: number; name: string } | null {
  return PRODUCTS[productId] ?? null;
}

export async function confirmOnce(
  order: Order,
  userId: string,
  request: ConfirmationRequest,
  dependencies: ApprovalDependencies,
): Promise<string> {
  if (request.orderId !== order.order_id || !request.paymentKey) return "invalid_request";
  if (order.user_id !== userId) return "not_owner";
  if (!Number.isSafeInteger(request.amount) || request.amount !== order.amount) return "amount_mismatch";
  if (order.status === "paid") {
    return order.payment_key === request.paymentKey ? "already_paid" : "already_paid_conflict";
  }
  if (order.status !== "ready") return "invalid_status";

  const approved = await dependencies.requestApproval(request);
  if (approved.paymentKey !== request.paymentKey || approved.orderId !== order.order_id ||
      approved.totalAmount !== order.amount || approved.status !== "DONE") {
    return "provider_mismatch";
  }
  return await dependencies.grant(order, approved);
}
