export type ProgressEvent = {
  id: string;
  kind: "mission" | "distance";
  payload: Record<string, unknown>;
};

const EVENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,80}$/;
const ALLOWED_KINDS = new Set(["mission", "distance"]);
const MAX_EVENTS_PER_BATCH = 100;

export function validateEvents(value: unknown): ProgressEvent[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_EVENTS_PER_BATCH) {
    throw new Error("invalid_event_batch");
  }

  for (const item of value) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("invalid_event");
    }
    const event = item as Record<string, unknown>;
    if (typeof event.id !== "string" || !EVENT_ID_PATTERN.test(event.id) ||
        typeof event.kind !== "string" || !ALLOWED_KINDS.has(event.kind) ||
        !event.payload || typeof event.payload !== "object" || Array.isArray(event.payload)) {
      throw new Error("invalid_event");
    }
  }

  return value as ProgressEvent[];
}
