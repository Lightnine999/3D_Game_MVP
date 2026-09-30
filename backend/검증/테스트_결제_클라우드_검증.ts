// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// Synthetic database grant only. NEVER calls Toss Payments or confirms a real payment.
const ref = Deno.env.get("MVP_PROJECT_REF");
const url = Deno.env.get("SUPABASE_URL");
const publicKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (Deno.env.get("MVP_PAYMENT_WRITE_APPROVED") !== "yes" || ref !== "ecqfmaivywgzlbnqxymb" ||
    url !== `https://${ref}.supabase.co` || !publicKey || !serviceKey) {
  throw new Error("Explicit project and synthetic payment test approval required. No writes started.");
}

const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const guests: Array<{ id: string; client: typeof admin }> = [];
let testFailed = false;
let cleanupFailed = false;
function check(value: unknown, label: string): void {
  if (!value) throw new Error(`FAILED_${label}`);
  console.log(`PASS ${label}`);
}
function cleanupError(label: string): void {
  console.error(label);
  cleanupFailed = true;
}

try {
  const before = await admin.auth.admin.listUsers({ page: 1, perPage: 100 });
  check(!before.error && before.data.users.length === 0, "empty_auth_baseline");
  for (let i = 0; i < 2; i++) {
    const client = createClient(url, publicKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const result = await client.auth.signInAnonymously();
    if (result.error || !result.data.user) throw new Error("FAILED_auth_sign_in");
    guests.push({ id: result.data.user.id, client });
    const readback = await admin.auth.admin.getUserById(result.data.user.id);
    check(!readback.error && readback.data.user?.id === result.data.user.id, "auth_created_readback");
  }
  const [first, second] = guests;
  check(first.id !== second.id, "distinct_users");
  for (const guest of guests) {
    const profile = await guest.client.functions.invoke("ensure-profile", { body: {} });
    check(!profile.error && profile.data?.profile?.user_id === guest.id, "profile_created");
  }

  const forged = await first.client.functions.invoke("create-toss-order", {
    body: { product_id: "ammo_start_pack", amount: 1, user_id: second.id },
  });
  const rejected = forged.error?.context;
  const rejectedBody = rejected instanceof Response ? await rejected.clone().json() : null;
  check(rejected instanceof Response && rejected.status === 400 && rejectedBody?.error === "client_amount_forbidden",
    "client_amount_rejected_before_insert");

  const created = await first.client.functions.invoke("create-toss-order", { body: { product_id: "ammo_start_pack" } });
  check(!created.error && created.data?.amount === 1100 && created.data?.status === "ready" &&
    typeof created.data?.orderId === "string", "server_price_order_created");
  const orderId: string = created.data.orderId;
  const ownOrder = await first.client.from("toss_orders").select("order_id,amount,status").eq("order_id", orderId);
  const otherOrder = await second.client.from("toss_orders").select("order_id").eq("order_id", orderId);
  check(!ownOrder.error && ownOrder.data?.length === 1 && ownOrder.data[0].amount === 1100 &&
    !otherOrder.error && otherOrder.data?.length === 0, "order_readback_and_rls");

  const tampered = await first.client.functions.invoke("confirm-toss-payment", {
    body: { paymentKey: "synthetic_not_a_toss_result", orderId, amount: 100 },
  });
  const invalid = tampered.error?.context;
  const invalidBody = invalid instanceof Response ? await invalid.clone().json() : null;
  check(invalid instanceof Response && invalid.status === 400 && invalidBody?.error === "amount_mismatch",
    "amount_rejected_before_toss_call");
  const clientPurchase = await first.client.from("purchases").insert({
    user_id: first.id, order_id: orderId, payment_key: "synthetic_client", product_id: "ammo_start_pack", amount: 1100,
  });
  check(!!clientPurchase.error, "client_cannot_grant_purchase");

  // Bypasses Toss deliberately: this validates only the database atomic/idempotent grant.
  const fakeKey = `synthetic_${crypto.randomUUID()}`;
  const args = { p_order_id: orderId, p_user_id: first.id, p_payment_key: fakeKey, p_amount: 1100 };
  const both = await Promise.all([admin.rpc("finalize_payment", args), admin.rpc("finalize_payment", args)]);
  check(both.every((result) => !result.error) &&
    both.map((result) => result.data).sort().join(",") === "already_paid,paid", "concurrent_db_grant_once");
  const repeated = await admin.rpc("finalize_payment", args);
  const changedKey = await admin.rpc("finalize_payment", { ...args, p_payment_key: "synthetic_other" });
  check(!repeated.error && repeated.data === "already_paid" && !!changedKey.error, "same_key_retry_only");

  const order = await first.client.from("toss_orders").select("status").eq("order_id", orderId).single();
  const purchases = await first.client.from("purchases").select("payment_key").eq("order_id", orderId);
  const inventory = await first.client.from("inventory").select("quantity").eq("item_id", "ammo_start_pack");
  const otherPurchases = await second.client.from("purchases").select("id").eq("order_id", orderId);
  check(!order.error && order.data?.status === "paid" && !purchases.error && purchases.data?.length === 1 &&
    !inventory.error && inventory.data?.length === 1 && inventory.data[0].quantity === 1 &&
    !otherPurchases.error && otherPurchases.data?.length === 0, "paid_and_inventory_once_readback");
  console.log("MVP_PAYMENT_DB_ONLY_PASS (Toss API not called)");
} catch {
  // Do not print paymentKey, JWT, user IDs, provider payload or server secrets.
  console.error("MVP_PAYMENT_DB_ONLY_FAILED_SAFELY");
  testFailed = true;
} finally {
  for (const guest of guests) {
    try {
      const deletion = await admin.auth.admin.deleteUser(guest.id);
      const readback = await admin.auth.admin.getUserById(guest.id);
      if (deletion.error || !readback.error) cleanupError("TEST_USER_CLEANUP_FAILED");
    } catch {
      cleanupError("TEST_USER_CLEANUP_FAILED");
    }
  }
  if (guests.length) {
    const ids = guests.map((guest) => guest.id);
    for (const [table, column] of [
      ["profiles", "id"], ["toss_orders", "user_id"], ["purchases", "user_id"], ["inventory", "user_id"],
    ]) {
      try {
        const rows = await admin.from(table).select(column).in(column, ids);
        if (rows.error || rows.data?.length !== 0) cleanupError("TEST_ROW_CLEANUP_FAILED");
      } catch {
        cleanupError("TEST_ROW_CLEANUP_FAILED");
      }
    }
  }
  console.log(cleanupFailed ? "MVP_PAYMENT_CLEANUP_INCOMPLETE" : "MVP_PAYMENT_TEST_DATA_CLEAN");
}
if (testFailed || cleanupFailed) Deno.exit(1);
