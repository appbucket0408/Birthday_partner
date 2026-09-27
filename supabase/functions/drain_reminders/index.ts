// The deployed entry point. All the logic lives in handler.ts, which has no
// Deno.serve of its own so tests can import it without starting a server.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleDrain } from "./handler.ts";

Deno.serve((req: Request): Promise<Response> => {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const client = url && serviceKey ? createClient(url, serviceKey) : null;
  return handleDrain(req, {
    env: (k) => Deno.env.get(k),
    admin: {
      // awaited, not returned: PostgrestFilterBuilder is thenable but is
      // not a Promise, so it does not satisfy the deps type directly.
      rpc: async (fn, params) => await client!.rpc(fn, params),
      deleteDeviceToken: async (token) =>
        await client!.from("device_tokens").delete().eq("token", token),
    },
    fetchImpl: fetch,
    now: () => Date.now(),
  });
});
