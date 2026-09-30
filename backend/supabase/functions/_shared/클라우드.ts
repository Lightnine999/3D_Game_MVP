export type CloudConfig = { url: string; publicKey: string; serviceKey: string };
export type EnvironmentLookup = (name: string) => string | undefined;

export function readCloudConfig(get: EnvironmentLookup): CloudConfig {
  const url = get("SUPABASE_URL");
  const publicKey = get("SUPABASE_ANON_KEY") || get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publicKey || !serviceKey) throw new Error("server_not_configured");
  return { url, publicKey, serviceKey };
}
