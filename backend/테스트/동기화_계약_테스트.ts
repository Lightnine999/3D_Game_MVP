import assert from "node:assert/strict";

// Load at runtime so RED is a failed behavior test, not a TypeScript import error.
const moduleUrl = new URL("../supabase/functions/_shared/동기화.ts", import.meta.url).href;

Deno.test("진행 이벤트는 고유 ID와 원본 payload를 보존한다", async () => {
  const { validateEvents } = await import(moduleUrl);
  const events = [{ id: "evt_001", kind: "mission", payload: { stage_id: "field_01", mission_id: "M1" } }];

  assert.deepEqual(validateEvents(events), events);
});

Deno.test("구매·관리자 이벤트는 진행 동기화로 받을 수 없다", async () => {
  const { validateEvents } = await import(moduleUrl);

  for (const kind of ["purchase", "inventory", "admin"]) {
    assert.throws(
      () => validateEvents([{ id: "evt_002", kind, payload: {} }]),
      /invalid_event/,
    );
  }
});

Deno.test("빈 묶음·과도한 묶음·잘못된 ID와 payload를 거부한다", async () => {
  const { validateEvents } = await import(moduleUrl);

  assert.throws(() => validateEvents([]), /invalid_event_batch/);
  assert.throws(
    () => validateEvents(Array.from({ length: 101 }, (_, i) => ({ id: `evt_${i}`, kind: "distance", payload: {} }))),
    /invalid_event_batch/,
  );
  assert.throws(() => validateEvents([{ id: "space id", kind: "mission", payload: {} }]), /invalid_event/);
  assert.throws(() => validateEvents([{ id: "evt_003", kind: "mission", payload: [] }]), /invalid_event/);
});
