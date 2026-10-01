export type SupportRequest = {
  kind: "question" | "bug";
  message: string;
  bugContext: Record<string, unknown> | null;
  threadId: string | null;
};

const MAX_MESSAGE_LENGTH = 2000;
const MAX_CONTEXT_BYTES = 8192;
const THREAD_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function validateSupportRequest(value: unknown): SupportRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_support_request");
  }
  const input = value as Record<string, unknown>;
  const message = typeof input.message === "string" ? input.message.trim() : "";
  if ((input.kind !== "question" && input.kind !== "bug") ||
      !message || message.length > MAX_MESSAGE_LENGTH) {
    throw new Error("invalid_support_request");
  }
  const rawContext = input.bug_context;
  if (rawContext !== undefined && rawContext !== null &&
      (typeof rawContext !== "object" || Array.isArray(rawContext) ||
       new TextEncoder().encode(JSON.stringify(rawContext)).length > MAX_CONTEXT_BYTES)) {
    throw new Error("invalid_support_request");
  }
  if (input.kind === "question" && rawContext != null) throw new Error("invalid_support_request");
  const threadId = input.threadId === undefined ? null : input.threadId;
  if (threadId !== null && (typeof threadId !== "string" || !THREAD_ID_PATTERN.test(threadId) || input.kind !== "question")) {
    throw new Error("invalid_support_request");
  }
  return {
    kind: input.kind,
    message,
    bugContext: rawContext == null ? null : rawContext as Record<string, unknown>,
    threadId: threadId === null ? null : threadId.toLowerCase(),
  };
}

export function needsHuman(kind: SupportRequest["kind"], message: string): boolean {
  return kind === "bug" || /결제|환불|구매|카드|payment|refund|purchase|charge/i.test(message);
}
