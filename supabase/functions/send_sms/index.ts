// The deployed entry point. All the logic lives in handler.ts, which has no
// Deno.serve of its own so tests can import it without starting a server.
import { handleSendSms } from "./handler.ts";

Deno.serve((req: Request): Promise<Response> =>
  handleSendSms(req, {
    env: (k) => Deno.env.get(k),
    fetchImpl: fetch,
  })
);
