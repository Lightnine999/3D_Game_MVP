// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// Scope: two disposable anonymous accounts; direct-write denials and stale JWT after self-deletion.
const ref = Deno.env.get("MVP_PROJECT_REF");
const url = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (Deno.env.get("MVP_SECURITY_WRITE_APPROVED") !== "yes" || ref !== "ecqfmaivywgzlbnqxymb" ||
    url !== `https://${ref}.supabase.co` || !anonKey || !serviceKey) {
  throw new Error("Explicit Server 1 S1/S8 approval required. No writes started.");
}
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const guests: Array<{ id: string; token: string; client: typeof admin }> = [];
let failed = false;
let cleanupFailed = false;
function check(ok: unknown, label: string): void {
  if (!ok) throw new Error(`FAILED_${label}`);
  console.log(`PASS ${label}`);
}
try {
  const baseline = await admin.auth.admin.listUsers({ page: 1, perPage: 100 });
  check(!baseline.error && baseline.data.users.length === 0, "empty_auth_baseline");
  for (let i = 0; i < 2; i++) {
    const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const signedIn = await client.auth.signInAnonymously();
    if (signedIn.error || !signedIn.data.user || !signedIn.data.session?.access_token) {
      throw new Error("FAILED_auth_sign_in");
    }
    guests.push({ id: signedIn.data.user.id, token: signedIn.data.session.access_token, client });
  }
  const [victim, survivor] = guests;
  check(victim.id !== survivor.id, "two_distinct_guests");
  for (const guest of guests) {
    const profile = await guest.client.functions.invoke("ensure-profile", { body: {} });
    check(!profile.error && profile.data?.profile?.user_id === guest.id, "profile_created");
  }
  const fakeThread = crypto.randomUUID();
  const fakeOrder = `denied_${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;
  const attempts: Array<[string, () => PromiseLike<{ error: { code?: string } | null }>]> = [
    ["toss_orders", () => victim.client.from("toss_orders").insert({
      order_id: fakeOrder, user_id: victim.id, product_id: "ammo_start_pack", amount: 1100, status: "paid",
    })],
    ["purchases", () => victim.client.from("purchases").insert({
      user_id: victim.id, order_id: fakeOrder, payment_key: "synthetic_denied", product_id: "ammo_start_pack", amount: 1100,
    })],
    ["inventory", () => victim.client.from("inventory").insert({
      user_id: victim.id, item_id: "ammo_start_pack", quantity: 99,
    })],
    ["support_threads", () => victim.client.from("support_threads").insert({
      user_id: survivor.id, kind: "question", status: "ai_answered",
    })],
    ["support_messages", () => victim.client.from("support_messages").insert({
      thread_id: fakeThread, role: "team", content: "위조 응답",
    })],
    ["bug_context", () => victim.client.from("bug_context").insert({
      thread_id: fakeThread, app_version: "fake",
    })],
    ["chat_usage", () => victim.client.from("chat_usage").insert({
      user_id: victim.id, day: new Date().toISOString().slice(0, 10), count: 30,
    })],
  ];
  for (const [table, request] of attempts) {
    const result = await request();
    check(result.error?.code === "42501", `direct_insert_denied_${table}`);
  }
  const changedRole = await victim.client.from("profiles").update({ role: "admin" }).eq("id", victim.id);
  check(changedRole.error?.code === "42501", "self_admin_role_update_denied");

  const deleted = await victim.client.functions.invoke("delete-account", { body: { confirm: true } });
  check(!deleted.error && deleted.data?.status === "deleted", "self_delete_succeeded");
  const stale = await fetch(`${url}/functions/v1/ensure-profile`, {
    method: "POST",
    headers: { authorization: `Bearer ${victim.token}`, apikey: anonKey, "content-type": "application/json" },
    body: "{}",
  });
  check(stale.status === 401, "stale_jwt_rejected_by_edge_auth");
  const gone = await admin.auth.admin.getUserById(victim.id);
  const victimProfile = await admin.from("profiles").select("id").eq("id", victim.id);
  const kept = await admin.auth.admin.getUserById(survivor.id);
  const survivorProfile = await admin.from("profiles").select("id").eq("id", survivor.id);
  check(!!gone.error && !victimProfile.error && victimProfile.data?.length === 0 &&
    !kept.error && !survivorProfile.error && survivorProfile.data?.length === 1,
    "deleted_user_gone_other_user_intact");
  console.log("MVP_SECURITY_S1_S8_PASS (no provider calls)");
} catch {
  console.error("MVP_SECURITY_S1_S8_FAILED_SAFELY");
  failed = true;
} finally {
  for (const guest of guests) {
    try {
      const existing = await admin.auth.admin.getUserById(guest.id);
      if (!existing.error) {
        const deleted = await admin.auth.admin.deleteUser(guest.id);
        if (deleted.error) cleanupFailed = true;
      }
      const readback = await admin.auth.admin.getUserById(guest.id);
      const profiles = await admin.from("profiles").select("id").eq("id", guest.id);
      if (!readback.error || profiles.error || profiles.data?.length !== 0) cleanupFailed = true;
    } catch {
      cleanupFailed = true;
    }
  }
  console.log(cleanupFailed ? "MVP_SECURITY_S1_S8_TEST_DATA_CLEANUP_INCOMPLETE" : "MVP_SECURITY_S1_S8_TEST_DATA_CLEAN");
}
if (failed || cleanupFailed) Deno.exit(1);
