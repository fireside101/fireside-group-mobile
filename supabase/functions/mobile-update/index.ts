// CANDIDATE ONLY. Requires separately reviewed SQL, server secrets, deployment,
// gateway verification and per-subject gateway rate limits before activation.
import { createHandler } from './handler.mjs';
Deno.serve(createHandler({
  url: Deno.env.get('SUPABASE_URL'),
  serverKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
}));
