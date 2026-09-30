// deno-lint-ignore no-import-prefix
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// This script writes to Supabase Cloud. Never run without exact-project approval.
const ref = Deno.env.get("MVP_PROJECT_REF");
const url = Deno.env.get("SUPABASE_URL");
const publicKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (Deno.env.get("MVP_CLOUD_WRITE_APPROVED") !== "yes" || ref !== "ecqfmaivywgzlbnqxymb" ||
    url !== `https://${ref}.supabase.co` || !publicKey || !serviceKey) {
  throw new Error("Cloud approval, exact project and runtime keys are required. No writes started.");
}

const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const guests: Array<{ id: string; client: typeof admin }> = [];
let failed = false;
let cleanupFailed = false;

function check(value: unknown, label: string): void {
  if (!value) throw new Error(`FAILED_${label}`);
  console.log(`PASS ${label}`);
}

function cleanupError(label: string): void {
  console.error(label);
  cleanupFailed = true;
  failed = true;
}

try {
  const existing = await admin.auth.admin.listUsers({ page: 1, perPage: 100 });
  check(!existing.error && existing.data.users.length === 0, "empty_auth_baseline");

  for (let i = 0; i < 2; i++) {
    const client = createClient(url, publicKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const signed = await client.auth.signInAnonymously();
    if (signed.error || !signed.data.user) throw new Error("FAILED_anonymous_sign_in");
    guests.push({ id: signed.data.user.id, client });
    const readback = await admin.auth.admin.getUserById(signed.data.user.id);
    check(!readback.error && readback.data.user?.id === signed.data.user.id, "auth_user_readback");
  }
  const [first, second] = guests;
  check(first.id !== second.id, "distinct_users");

  for (const guest of guests) {
    const result = await guest.client.functions.invoke("ensure-profile", { body: {} });
    check(!result.error && result.data?.profile?.user_id === guest.id && result.data.profile.is_guest === true,
      "profile_created_from_auth");
  }

  const eventId = `mvp_${crypto.randomUUID()}`;
  const event = { id: eventId, kind: "mission", payload: { stage_id: "field_01", mission_id: "M1" } };
  const firstSync = await first.client.functions.invoke("sync-progress", { body: { events: [event], user_id: second.id } });
  const retry = await first.client.functions.invoke("sync-progress", { body: { events: [event] } });
  check(!firstSync.error && firstSync.data?.received === 1 && firstSync.data?.inserted === 1,
    "first_sync_from_verified_user");
  check(!retry.error && retry.data?.inserted === 0, "duplicate_not_reinserted");

  const own = await first.client.from("sync_events").select("client_event_id").eq("client_event_id", eventId);
  const other = await second.client.from("sync_events").select("client_event_id").eq("client_event_id", eventId);
  const ownMission = await first.client.from("mission_progress").select("stage_id,mission_id").eq("mission_id", "M1");
  const otherMission = await second.client.from("mission_progress").select("stage_id,mission_id").eq("mission_id", "M1");
  check(!own.error && own.data?.length === 1 && !other.error && other.data?.length === 0,
    "events_readback_and_rls");
  check(!ownMission.error && ownMission.data?.length === 1 && !otherMission.error && otherMission.data?.length === 0,
    "mission_readback_and_rls");

  const foreignProfile = await second.client.from("profiles").select("id").eq("id", first.id);
  const selfPromotion = await second.client.from("profiles").update({ role: "admin" }).eq("id", second.id);
  const directEvent = await first.client.from("sync_events").insert({
    user_id: first.id, client_event_id: `direct_${crypto.randomUUID()}`, kind: "mission", payload: event.payload,
  });
  check(!foreignProfile.error && foreignProfile.data?.length === 0, "profile_rls");
  check(!!selfPromotion.error && !!directEvent.error, "client_write_denied");

  const promote = await admin.from("profiles").update({ role: "admin" }).eq("id", first.id);
  check(!promote.error, "admin_setup_for_role_preservation");
  const repeated = await first.client.functions.invoke("ensure-profile", { body: { role: "user", is_guest: false } });
  check(!repeated.error && repeated.data?.profile?.role === "admin" && repeated.data.profile.is_guest === true,
    "profile_role_preserved");

  const invalid = await second.client.functions.invoke("sync-progress", {
    body: { events: [{ id: `bad_${crypto.randomUUID()}`, kind: "purchase", payload: {} }] },
  });
  const invalidResponse = invalid.error?.context;
  const invalidBody = invalidResponse instanceof Response ? await invalidResponse.clone().json() : null;
  check(invalidResponse instanceof Response && invalidResponse.status === 400 &&
    invalidBody?.error === "invalid_event", "purchase_event_rejected_with_code");
  console.log("MVP_CLOUD_SLICE_PASS (no payment or LLM call)");
} catch {
  // Never log session tokens, user IDs, provider responses or sensitive errors.
  console.error("MVP_CLOUD_SLICE_FAILED_SAFELY");
  failed = true;
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
    for (const [table, column] of [["profiles", "id"], ["sync_events", "user_id"], ["mission_progress", "user_id"]]) {
      try {
        const rows = await admin.from(table).select(column).in(column, ids);
        if (rows.error || rows.data?.length !== 0) cleanupError("TEST_ROW_CLEANUP_FAILED");
      } catch {
        cleanupError("TEST_ROW_CLEANUP_FAILED");
      }
    }
  }
  console.log(cleanupFailed ? "MVP_CLOUD_CLEANUP_INCOMPLETE" : "MVP_CLOUD_TEST_DATA_CLEAN");
}
if (failed) Deno.exit(1);
