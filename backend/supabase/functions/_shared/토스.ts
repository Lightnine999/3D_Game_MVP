import type { ApprovalResponse, ConfirmationRequest } from "./결제.ts";

type FetchLike = (url: string, init: RequestInit) => Promise<Response>;
const CONFIRM_URL = "https://api.tosspayments.com/v1/payments/confirm";

/** Calls the Toss test approval API only from a server-side Edge Function. */
export async function confirmPaymentWithToss(
  secretKey: string,
  request: ConfirmationRequest,
  fetcher: FetchLike = fetch,
): Promise<ApprovalResponse> {
  if (!secretKey.startsWith("test_sk_") && !secretKey.startsWith("test_gsk_")) {
    throw new Error("test_secret_required");
  }
  if (!request.paymentKey || !request.orderId || !Number.isSafeInteger(request.amount) || request.amount <= 0) {
    throw new Error("invalid_confirmation_request");
  }

  let response: Response;
  try {
    response = await fetcher(CONFIRM_URL, {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${secretKey}:`)}`,
        "Content-Type": "application/json",
        "Idempotency-Key": request.orderId,
      },
      body: JSON.stringify(request),
    });
  } catch {
    throw new Error("toss_confirmation_rejected");
  }
  if (!response.ok) throw new Error("toss_confirmation_rejected");

  let value: unknown;
  try {
    value = await response.json();
  } catch {
    throw new Error("invalid_toss_response");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_toss_response");
  const data = value as Record<string, unknown>;
  if (typeof data.paymentKey !== "string" || typeof data.orderId !== "string" ||
      typeof data.totalAmount !== "number" || typeof data.status !== "string") {
    throw new Error("invalid_toss_response");
  }
  return {
    paymentKey: data.paymentKey,
    orderId: data.orderId,
    totalAmount: data.totalAmount,
    status: data.status,
  };
}
