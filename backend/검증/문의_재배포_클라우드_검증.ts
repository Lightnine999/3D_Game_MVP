// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// Scope: one bug report, two disposable anonymous users; no LLM, administrator or Toss call.
const ref = Deno.env.get("MVP_PROJECT_REF");
const url = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (Deno.env.get("MVP_SUPPORT_REDEPLOY_APPROVED") !== "yes" || ref !== "ecqfmaivywgzlbnqxymb" ||
    url !== `https://${ref}.supabase.co` || !anonKey || !serviceKey) {
  throw new Error("Explicit Server 1 support-chat retest approval required. No writes started.");
}
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const guests: Array<{ id: string; client: typeof admin }> = [];
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
    const created = await client.auth.signInAnonymously();
    if (created.error || !created.data.user) throw new Error("FAILED_auth_sign_in");
    guests.push({ id: created.data.user.id, client });
  }
  check(guests.length === 2 && guests[0].id !== guests[1].id, "two_distinct_guests");
  const owner = guests[0];
  const other = guests[1];
  const bug = await owner.client.functions.invoke("support-chat", { body: {
    kind: "bug", message: "재배포 후 제보 검증", bug_context: { app_version: "0.1.0", device_model: "test-device" },
  } });
  check(!bug.error && bug.data?.status === "needs_human" && bug.data?.reply === "팀에 전달했어요" &&
    typeof bug.data?.threadId === "string", "bug_routes_to_human_without_llm");
  const threadId: string = bug.data.threadId;
  const own = await owner.client.from("support_threads").select("id,status").eq("id", threadId);
  const denied = await other.client.from("support_threads").select("id").eq("id", threadId);
  const details = await owner.client.from("bug_context").select("app_version").eq("thread_id", threadId);
  check(!own.error && own.data?.length === 1 && !denied.error && denied.data?.length === 0 &&
    !details.error && details.data?.length === 1, "bug_context_owner_only_readback");
  console.log("MVP_SUPPORT_REDEPLOY_BUG_ROUTE_PASS (OpenAI not called)");
} catch {
  console.error("MVP_SUPPORT_REDEPLOY_BUG_ROUTE_FAILED_SAFELY");
  failed = true;
} finally {
  for (const guest of guests) {
    try {
      const deleted = await admin.auth.admin.deleteUser(guest.id);
      const checkGone = await admin.auth.admin.getUserById(guest.id);
      if (deleted.error || !checkGone.error) cleanupFailed = true;
    } catch {
      cleanupFailed = true;
    }
  }
  if (guests.length) {
    const ids = guests.map((guest) => guest.id);
    for (const [table, column] of [["support_threads", "user_id"], ["chat_usage", "user_id"]]) {
      try {
        const rows = await admin.from(table).select(column).in(column, ids);
        if (rows.error || rows.data?.length !== 0) cleanupFailed = true;
      } catch {
        cleanupFailed = true;
      }
    }
  }
  console.log(cleanupFailed ? "MVP_SUPPORT_REDEPLOY_TEST_DATA_CLEANUP_INCOMPLETE" : "MVP_SUPPORT_REDEPLOY_TEST_DATA_CLEAN");
}
if (failed || cleanupFailed) Deno.exit(1);
