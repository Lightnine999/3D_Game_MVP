// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// Cloud writes: two disposable anonymous users, bug reports, admin reply and self-deletion.
// No OpenAI or Toss call; provider keys are never loaded by this script.
const ref = Deno.env.get("MVP_PROJECT_REF");
const url = Deno.env.get("SUPABASE_URL");
const publicKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (Deno.env.get("MVP_SUPPORT_WRITE_APPROVED") !== "yes" || ref !== "ecqfmaivywgzlbnqxymb" ||
    url !== `https://${ref}.supabase.co` || !publicKey || !serviceKey) {
  throw new Error("Explicit Server 1 support/admin/deletion approval required. No writes started.");
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
async function errorBody(error: { context?: unknown } | null): Promise<{ status: number; code: string | null }> {
  const context = error?.context;
  if (!(context instanceof Response)) return { status: 0, code: null };
  const body: unknown = await context.clone().json();
  const code = body && typeof body === "object" ? (body as Record<string, unknown>).error : null;
  return { status: context.status, code: typeof code === "string" ? code : null };
}

try {
  const before = await admin.auth.admin.listUsers({ page: 1, perPage: 100 });
  check(!before.error && before.data.users.length === 0, "empty_auth_baseline");
  for (let i = 0; i < 2; i++) {
    const client = createClient(url, publicKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const created = await client.auth.signInAnonymously();
    if (created.error || !created.data.user) throw new Error("FAILED_auth_sign_in");
    guests.push({ id: created.data.user.id, client });
    const readback = await admin.auth.admin.getUserById(created.data.user.id);
    check(!readback.error && readback.data.user?.id === created.data.user.id, "auth_created_readback");
  }
  const [manager, player] = guests;
  check(manager.id !== player.id, "distinct_users");
  for (const guest of guests) {
    const profile = await guest.client.functions.invoke("ensure-profile", { body: {} });
    check(!profile.error && profile.data?.profile?.user_id === guest.id, "profile_created");
  }
  const promoted = await admin.from("profiles").update({ role: "admin" }).eq("id", manager.id);
  check(!promoted.error, "test_admin_role_set");

  const bug = await player.client.functions.invoke("support-chat", { body: {
    kind: "bug", message: "화면 진행이 멈췄어요",
    bug_context: { app_version: "0.1.0", platform: "android", device_model: "test-device", os_version: "test-os", last_run: { distance_m: 12 } },
  } });
  check(!bug.error && bug.data?.status === "needs_human" && typeof bug.data?.threadId === "string",
    "bug_report_saved_without_llm");
  const threadId: string = bug.data.threadId;
  const own = await player.client.from("support_threads").select("id,status").eq("id", threadId);
  const context = await player.client.from("bug_context").select("app_version,last_run").eq("thread_id", threadId);
  check(!own.error && own.data?.length === 1 && !context.error && context.data?.length === 1,
    "bug_thread_context_readback");

  const denied = await player.client.functions.invoke("admin-overview", { body: { section: "members" } });
  const deniedResult = await errorBody(denied.error);
  check(deniedResult.status === 403 && deniedResult.code === "forbidden", "normal_user_admin_denied");
  const directView = await player.client.from("admin_members").select("user_id");
  check(!!directView.error, "admin_view_not_granted_to_app_role");
  const members = await manager.client.functions.invoke("admin-overview", { body: { section: "members" } });
  const support = await manager.client.functions.invoke("admin-overview", { body: { section: "support" } });
  check(!members.error && members.data?.items?.length === 2 &&
    !support.error && support.data?.items?.some((item: { thread_id: string }) => item.thread_id === threadId),
    "admin_member_support_views");

  const forgedReply = await player.client.functions.invoke("admin-support-reply", {
    body: { threadId, reply: "위조 답변", status: "closed", admin_id: manager.id },
  });
  check((await errorBody(forgedReply.error)).status === 403, "normal_user_reply_denied");
  const directRpc = await admin.rpc("admin_reply", {
    p_admin_id: player.id, p_thread_id: threadId, p_reply: "위조 답변", p_status: "closed",
  });
  check(!!directRpc.error, "database_admin_role_rechecked");
  const reply = await manager.client.functions.invoke("admin-support-reply", {
    body: { threadId, reply: "확인 후 처리했습니다.", status: "closed" },
  });
  const ownClosed = await player.client.from("support_threads").select("status").eq("id", threadId).single();
  const messages = await player.client.from("support_messages").select("role,content").eq("thread_id", threadId);
  check(!reply.error && reply.data?.status === "closed" && !ownClosed.error && ownClosed.data?.status === "closed" &&
    !messages.error && messages.data?.some((item) => item.role === "team"), "team_reply_and_status_readback");

  const usageSetup = await admin.from("chat_usage").update({ count: 29 }).eq("user_id", player.id);
  check(!usageSetup.error, "synthetic_usage_29");
  const thirtieth = await player.client.functions.invoke("support-chat", { body: { kind: "bug", message: "한도 경계 제보" } });
  const thirtyFirst = await player.client.functions.invoke("support-chat", { body: { kind: "bug", message: "한도 초과 제보" } });
  const limit = await errorBody(thirtyFirst.error);
  const usage = await admin.from("chat_usage").select("count").eq("user_id", player.id).single();
  const threads = await admin.from("support_threads").select("id").eq("user_id", player.id);
  check(!thirtieth.error && thirtieth.data?.status === "needs_human" && limit.status === 429 &&
    limit.code === "daily_limit_reached" && !usage.error && usage.data?.count === 30 &&
    !threads.error && threads.data?.length === 2, "daily_limit_30_blocks_31");

  const selfDelete = await player.client.functions.invoke("delete-account", {
    body: { confirm: true, user_id: manager.id },
  });
  const removed = await admin.auth.admin.getUserById(player.id);
  const managerStillThere = await admin.auth.admin.getUserById(manager.id);
  const oldThreads = await admin.from("support_threads").select("id").eq("user_id", player.id);
  check(!selfDelete.error && selfDelete.data?.status === "deleted" && !!removed.error &&
    !managerStillThere.error && !oldThreads.error && oldThreads.data?.length === 0,
    "self_delete_preserves_other_user_and_cascades");
  console.log("MVP_SUPPORT_ADMIN_DELETE_SLICE_PASS (OpenAI not called)");
} catch {
  console.error("MVP_SUPPORT_ADMIN_DELETE_SLICE_FAILED_SAFELY");
  testFailed = true;
} finally {
  for (const guest of guests) {
    try {
      const existing = await admin.auth.admin.getUserById(guest.id);
      if (!existing.error) {
        const deletion = await admin.auth.admin.deleteUser(guest.id);
        if (deletion.error) cleanupError("TEST_USER_CLEANUP_FAILED");
      }
      const readback = await admin.auth.admin.getUserById(guest.id);
      if (!readback.error) cleanupError("TEST_USER_CLEANUP_FAILED");
    } catch {
      cleanupError("TEST_USER_CLEANUP_FAILED");
    }
  }
  if (guests.length) {
    const ids = guests.map((guest) => guest.id);
    for (const [table, column] of [["profiles", "id"], ["support_threads", "user_id"], ["chat_usage", "user_id"]]) {
      try {
        const rows = await admin.from(table).select(column).in(column, ids);
        if (rows.error || rows.data?.length !== 0) cleanupError("TEST_ROW_CLEANUP_FAILED");
      } catch {
        cleanupError("TEST_ROW_CLEANUP_FAILED");
      }
    }
  }
  console.log(cleanupFailed ? "MVP_SUPPORT_TEST_DATA_CLEANUP_INCOMPLETE" : "MVP_SUPPORT_TEST_DATA_CLEAN");
}
if (testFailed || cleanupFailed) Deno.exit(1);
