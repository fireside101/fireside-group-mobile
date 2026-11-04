# Owner-run mobile DB / credential activation package

**Local, rehearsed, not executed against production.** Joseph remains the production SQL operator. This is an executable paused bootstrap, not authorization for this agent to run production SQL. No Argo, GitHub, Kubernetes, bucket, deployed function, or production Secret was changed by this package.

## Exact operator command

After the reviewed package is present on the approved secure owner execution host, with the existing release Python environment and private input provisioned there:

```sh
/home/nderitu/.hermes/cache/scratch/mobile-transport-venv/bin/python \
  /home/nderitu/work/fireside-group-mobile/supabase/activation/activate.py \
  install-paused --owner-approved \
  --output /home/nderitu/.config/fireside-mobile/issued-01 \
  < /home/nderitu/.config/fireside-mobile/owner-input.json
```

This is the single DB/bootstrap operation. It does **not** unpause publication or claim deployed custom-role transport works. The interpreter above was exercised locally; production operator host needs Python 3.12+ and the same `psycopg[binary]` dependency, plus network access. Do not blindly transplant an agent-cache interpreter into an Argo image: freeze the tested dependency in the reviewed execution image instead. The output parent must already exist privately; the output directory must not exist. Clear all inherited `PG*` environment variables; never enable shell tracing or print the input/output files.

`owner-input.json` must be a regular file owned by the executing UID, mode **0600**, outside the checkout, provisioned through existing secure server custody (not chat, CI, an argv value, or a pasted terminal command). Its exact JSON keys are:

- `owner_dsn`: explicit libpq conninfo with `host=supabase.firesideafrica.cloud port=5433 dbname=postgres user=<approved-owner> password=<private-value> sslmode=verify-full sslrootcert=<absolute-existing-CA-file>`. The owner must be able to create/set roles, create the schema, change function ownership, grant exact Auth/PI columns and install Storage/Auth/PI policies. The current combined install is rehearsed with a superuser owner; a restricted administrator is **not** attested.
- `jwt_secret`: the current server-side HS256 JWT signing secret, at least 32 characters. This broad signing authority stays only in owner custody and process memory, never in generated publisher files, GitHub, source, or a phone. The wrapper does not retrieve it, rotate it, or guess it.

The CA file must be the approved `fireside-pg-ca` ConfigMap CA material, mounted/read through the approved versioned path. It is not a public-root fallback. The output DSN retains this absolute CA filename: the reviewed publisher execution must install the same approved CA at that path, or deliberately re-render the path in its own versioned adapter. A DSN string alone is not CA distribution.

## What actually runs

`activate.py` checks every SQL source against `sha256.json` before credentials/network IO, then composes `preflight.sql` → `202611030001_mobile_release.sql` → `202611040001_mobile_release_storage_authority.sql` → `candidates/mobile_private_delivery.sql` → `finalize.sql` in **one transaction**. Only standalone candidate BEGIN/COMMIT markers are removed; a RESET ROLE is inserted between sections. `verify.sql` runs before commit and again against the exact target afterward. Existing candidate files are unchanged. Do not run the three original candidates individually as a substitute.

- Refuse every preexisting mobile role/schema/public RPC, including seemingly safe identities; never silently adopt memberships, column grants, ownership or role defaults. Refuse PUBLIC Storage table/column/default privileges, public Storage definer exposure, and newly exposed PUBLIC identity definers. Shared defaults and unrelated ACLs are not repaired automatically.
- Fresh owner is NOLOGIN, NOINHERIT, no BYPASSRLS. All mobile functions, including replaced `advertise` and `public.mobile_update_authorize`, must be owned by it. Creator-default executors on the public RPC are removed by the original candidate; readback verifies the complete known executor matrix.
- Dedicated `mobile_release_registry_login` is LOGIN/NOINHERIT with **no memberships**, no ownership or table/column privileges, and only schema USAGE plus `allocate/reserve/advertise/receipt/latest` EXECUTE. It cannot control/unpause/revoke, SET ROLE to the owner, authorize employee subjects, or manipulate Storage. Its password is generated locally; only a SCRAM verifier enters SQL (never the raw password). Password authentication expires after **24 hours**.
- `mobile_release_storage_publisher` remains NOLOGIN, no memberships/ownership/BYPASSRLS. Its JWT has **one-hour expiry**; only the Storage backend's explicit authenticator→SET-role edge allows transport. It receives Storage object INSERT/SELECT and bucket SELECT, with restrictive private-bucket fences and no UPDATE/DELETE/UPSERT authority. It receives no registry or Auth/PI authority.
- Seed signer `701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9`, known published floor **5**, `paused=true`, no advertised artifact. The published APK is evidence for floor 5, **not** the maximum installed fleet code, installed fleet signer coverage, or a privately advertised release. Never invent a fleet maximum or seed the old public URL as a private artifact.
- Public RPC EXECUTE goes to the existing **server-only** `service_role`, as required by the current Edge adapter, not anon/authenticated/the publisher LOGIN/Storage role. This does not mint a service-role credential for CI or make the mobile schema PostgREST-exposed. The Edge server's existing broad server custody is separate from narrow CI publisher custody.

Two private files are created in a new 0700 directory: `publisher.json` (0600, narrow DSN/token and explicit current publisher contract), and `receipt.json` (0600, expiries and held boundaries). No secret values or upstream exceptions are printed. The wrapper independently opens the newly issued registry LOGIN using verify-full TLS and checks its own encrypted session, then reruns owner-side admission. If commit/readback/output fails, outcome may be **UNKNOWN**: retain private custody, inspect exact state, and use reviewed recovery; do not replay a non-idempotent install. No automatic DROP/rollback of already committed production objects is provided.

## Finite issuance / refresh

Use the same secure input and a new create-only directory immediately before a protected release promotion:

```sh
/home/nderitu/.hermes/cache/scratch/mobile-transport-venv/bin/python \
  /home/nderitu/work/fireside-group-mobile/supabase/activation/activate.py \
  refresh --owner-approved \
  --output /home/nderitu/.config/fireside-mobile/issued-02 \
  < /home/nderitu/.config/fireside-mobile/owner-input.json
```

Refresh re-admits installed role/function/table/column authority and Storage RLS/fences, rotates the registry password, checks real TLS/password login, and issues a fresh one-hour Storage token. It never reinstalls SQL or changes pause/floor/advertisement. A new registry password rejects previous passwords for new sessions; PostgreSQL password expiry does not kill already-open sessions. Old scoped JWTs remain valid until their one-hour expiration; their early revocation would need a separate owner operation (or project signing-key rotation, which is **not** proposed here). There is no refresh token, perpetual JWT, issuer key in CI, or hidden scheduled rotation. If fresh credentials cannot arrive through the approved versioned delivery, publication stops. Plan protected promotion within the one-hour window; long builds need just-in-time issuance, not a longer-lived privileged token.

## Required remaining bootstrap / live acceptance

1. Joseph executes the command through the approved owner path, with exact SQL hashes reviewed and secure server owner credential/JWT key/CA custody available. Package delivery/execution and secret distribution must use the versioned Argo workflow/platform path. **This package has no cluster-specific Argo executor or secret-distribution adapter; it cannot close that infrastructure requirement by itself.** Do not replace it with `kubectl create secret`, an unversioned hotpatch, or a broad DB/service key copied to Actions. The platform worker must bind the immutable reviewed source/image revision, exact Secret targets, protected publisher environment, custody/import and readback. Store only the narrow issued publisher fields in protected publisher custody; broad input never leaves the secure issuer.
2. Read back exact deployed DB roles/schema/functions/seed and private bucket state. Read-only MCP preparation observed PG **17.6**, no mobile roles/schema, private `fireside-mobile-releases` bucket with **200000000-byte** limit, zero PUBLIC Storage column grants/definer routines, no PUBLIC CREATE in public/auth/PI/storage, and no PUBLIC identity definer. These observations are not production SQL installation or universal ACL compatibility acceptance.
3. Explicit live custom-role **gateway and native Storage** acceptance remains unknown: exercise the actually deployed gateway's apikey/Authorization contract with the scoped JWT, insert a task-owned object, read its exact bytes, deny replacement/update/delete/another bucket, and show expired scoped-token rejection. Broad service-key transport success is not evidence. Do not silently alter Kong authentication or substitute global service_role in CI. The user must authorize the task-owned live writes; this local task did not perform them.
4. Verify deployed Edge wrapper and authenticated Auth→PI eligibility→private registry→short-lived signed URL→byte readback. Test revoked/inactive/duplicate/expired accounts, no anonymous directory or artifact read, revoked releases, and actual client parsing. No new advertised release exists just because SQL installs.
5. Resolve installed-fleet maximum/signer and real-device canary acceptance. Raise floor monotonically to an owner-verified maximum if above 5. Only after the approved prerequisites are proven may the owner explicitly call `mobile_release.control(false,NULL)` using owner/operator authority. This command is deliberately **not** embedded in bootstrap/refresh or granted to CI. Existing published code 5 is not fleet census.

## Rehearsal

```sh
/home/nderitu/.hermes/cache/scratch/mobile-transport-venv/bin/python \
  -m unittest discover -s supabase/tests/activation -v
```

Run from this checkout. Tests create and stop only their own private PG17 clusters using existing binaries, never shared socket 55479. The normal fixture is Unix-socket-only; the TLS test briefly restarts **its own** cluster on an ephemeral loopback port with a generated localhost certificate and SCRAM HBA. It exercises the real `run()` wrapper/combined SQL/private output/refresh with only production endpoint admission and owner-input source substituted for synthetic local custody. Actual production custom-role HTTP transport is not simulated as success. No test uses production credentials or network database endpoints.
