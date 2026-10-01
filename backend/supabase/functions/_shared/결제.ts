export type Order = {
  order_id: string;
  user_id: string;
  product_id: string;
  amount: number;
  catalog_version: number;
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

export type PackageProduct = {
  readonly product_id: string;
  readonly amount: number;
  readonly name: string;
  readonly components: Readonly<Record<string, number>>;
};

export const CATALOG_VERSION = 2;

// New sales only. Existing single-item orders are settled using their stored order.
const PRODUCTS: Readonly<Record<string, PackageProduct>> = Object.freeze({
  pack_survival_kit: Object.freeze({
    product_id: "pack_survival_kit", amount: 1100, name: "생존 키트",
    components: Object.freeze({ knife_plus: 1, ammo_start_pack: 1, flare_supply: 1, adrenaline: 1 }),
  }),
  pack_one_more: Object.freeze({
    product_id: "pack_one_more", amount: 3300, name: "한 번 더 패키지",
    components: Object.freeze({ revive: 1, frenzy_30: 1, bonfire: 1 }),
  }),
  pack_legend: Object.freeze({
    product_id: "pack_legend", amount: 5500, name: "전설의 생존자",
    components: Object.freeze({ revive: 2, knife_plus: 2, frenzy_30: 2, danger_sense: 2, gold_pistol: 1, supporter_badge: 1 }),
  }),
});

export function priceFor(productId: string): PackageProduct | null {
  return Object.hasOwn(PRODUCTS, productId) ? PRODUCTS[productId] : null;
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
  if (order.catalog_version !== 1 && order.catalog_version !== 2) return "unknown_catalog_version";
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
