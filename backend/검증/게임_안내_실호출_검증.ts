// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// EXACTLY two billable model questions on Server 1 after explicit approval; never print credentials or raw replies.
const ref = Deno.env.get("MVP_PROJECT_REF");
const url = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (Deno.env.get("MVP_GUIDE_TEST_APPROVED") !== "yes" || ref !== "ecqfmaivywgzlbnqxymb" ||
    url !== `https://${ref}.supabase.co` || !anonKey || !serviceKey) {
  throw new Error("Explicit Server 1 billable guide test approval required. No writes started.");
}
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
let testUserId: string | null = null;
let failed = false;
let cleanupFailed = false;
function check(ok: unknown, label: string): void {
  if (!ok) throw new Error(`FAILED_${label}`);
  console.log(`PASS ${label}`);
}
try {
  const initial = await admin.auth.admin.listUsers({ page: 1, perPage: 100 });
  check(!initial.error && initial.data.users.length === 0, "empty_auth_baseline");
  const signedIn = await client.auth.signInAnonymously();
  if (signedIn.error || !signedIn.data.user) throw new Error("FAILED_auth_sign_in");
  testUserId = signedIn.data.user.id;
  const known = await client.functions.invoke("support-chat", { body: {
    kind: "question", message: "테스트 안내 문구가 뭐야?",
  } });
  check(!known.error && known.data?.status === "ai_answered" &&
    known.data?.reply === "검증용 문구는 파란 구름 42입니다.", "template_fact_from_real_model");
  const unknown = await client.functions.invoke("support-chat", { body: {
    kind: "question", message: "실제 게임의 숨겨진 보물 이름은 뭐야?",
  } });
  check(!unknown.error && unknown.data?.status === "needs_human" &&
    unknown.data?.reply === "팀에 전달했어요", "unknown_game_fact_handed_to_team");
  const threads = await client.from("support_threads").select("id,status").eq("user_id", testUserId);
  check(!threads.error && threads.data?.length === 2 &&
    threads.data.some((row) => row.status === "ai_answered") &&
    threads.data.some((row) => row.status === "needs_human"), "two_thread_statuses_readback");
  console.log("MVP_TEST_GUIDE_REAL_MODEL_PASS (two provider requests)");
} catch {
  console.error("MVP_TEST_GUIDE_REAL_MODEL_FAILED_SAFELY");
  failed = true;
} finally {
  if (testUserId) {
    try {
      const deleted = await admin.auth.admin.deleteUser(testUserId);
      const userGone = await admin.auth.admin.getUserById(testUserId);
      const threadsGone = await admin.from("support_threads").select("id").eq("user_id", testUserId);
      if (deleted.error || !userGone.error || threadsGone.error || threadsGone.data?.length !== 0) cleanupFailed = true;
    } catch {
      cleanupFailed = true;
    }
  }
  console.log(cleanupFailed ? "MVP_TEST_GUIDE_USER_CLEANUP_INCOMPLETE" : "MVP_TEST_GUIDE_USER_CLEAN");
}
if (failed || cleanupFailed) Deno.exit(1);
