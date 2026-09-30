// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// One deliberately invalid paymentKey against the actual test approval path.
// This verifies rejection/no grant, NOT a successful Toss payment or SDK integration.
const ref = Deno.env.get("MVP_PROJECT_REF");
const url = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (Deno.env.get("MVP_TOSS_NEGATIVE_APPROVED") !== "yes" || ref !== "ecqfmaivywgzlbnqxymb" ||
    url !== `https://${ref}.supabase.co` || !anonKey || !serviceKey) {
  throw new Error("Explicit Server 1 Toss negative-path approval required. No writes started.");
}
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
let testUserId: string | null = null;
let failed = false;
let cleanupFailed = false;
function check(value: unknown, label: string): void {
  if (!value) throw new Error(`FAILED_${label}`);
  console.log(`PASS ${label}`);
}
try {
  const initial = await admin.auth.admin.listUsers({ page: 1, perPage: 100 });
  check(!initial.error && initial.data.users.length === 0, "empty_auth_baseline");
  const signedIn = await client.auth.signInAnonymously();
  if (signedIn.error || !signedIn.data.user) throw new Error("FAILED_auth_sign_in");
  testUserId = signedIn.data.user.id;
  const created = await client.functions.invoke("create-toss-order", { body: { product_id: "ammo_start_pack" } });
  check(!created.error && created.data?.status === "ready" && created.data?.amount === 1100 &&
    typeof created.data?.orderId === "string", "server_test_order_created");
  const orderId: string = created.data.orderId;
  const fakePaymentKey = `synthetic_negative_${crypto.randomUUID()}`;
  // Correct order and amount deliberately pass the server's preflight, reaching the Toss approval adapter.
  const confirmation = await client.functions.invoke("confirm-toss-payment", { body: {
    paymentKey: fakePaymentKey, orderId, amount: 1100,
  } });
  const context = confirmation.error?.context;
  const response = context instanceof Response ? context : null;
  let safeCode = "not_available";
  if (response) {
    try {
      const body: unknown = await response.clone().json();
      const raw = body && typeof body === "object" ? (body as Record<string, unknown>).error : null;
      if (raw === "toss_confirmation_failed" || raw === "test_key_missing") safeCode = raw;
    } catch {
      // Provider payloads and secret-bearing details are not logged.
    }
  }
  console.log(`TOSS_CONFIRM_HTTP=${response?.status ?? 0} SAFE_ERROR=${safeCode}`);
  check(response?.status === 502 && safeCode === "toss_confirmation_failed", "invalid_payment_rejected_by_server");
  const order = await client.from("toss_orders").select("status").eq("order_id", orderId).single();
  const purchases = await client.from("purchases").select("id").eq("order_id", orderId);
  const inventory = await client.from("inventory").select("quantity").eq("item_id", "ammo_start_pack");
  check(!order.error && order.data?.status === "ready" && !purchases.error && purchases.data?.length === 0 &&
    !inventory.error && inventory.data?.length === 0, "no_purchase_or_grant_after_rejection");
  console.log("MVP_TOSS_NEGATIVE_EDGE_PATH_PASS (provider-side request log not independently checked)");
} catch {
  console.error("MVP_TOSS_NEGATIVE_EDGE_PATH_FAILED_SAFELY");
  failed = true;
} finally {
  if (testUserId) {
    try {
      const deleted = await admin.auth.admin.deleteUser(testUserId);
      const userGone = await admin.auth.admin.getUserById(testUserId);
      const ordersGone = await admin.from("toss_orders").select("order_id").eq("user_id", testUserId);
      const purchasesGone = await admin.from("purchases").select("id").eq("user_id", testUserId);
      const inventoryGone = await admin.from("inventory").select("item_id").eq("user_id", testUserId);
      if (deleted.error || !userGone.error || ordersGone.error || ordersGone.data?.length !== 0 ||
          purchasesGone.error || purchasesGone.data?.length !== 0 || inventoryGone.error || inventoryGone.data?.length !== 0) {
        cleanupFailed = true;
      }
    } catch {
      cleanupFailed = true;
    }
  }
  console.log(cleanupFailed ? "MVP_TOSS_NEGATIVE_TEST_DATA_CLEANUP_INCOMPLETE" : "MVP_TOSS_NEGATIVE_TEST_DATA_CLEAN");
}
if (failed || cleanupFailed) Deno.exit(1);
