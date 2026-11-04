# Local private-delivery candidate (NOT deployed)

## Exact publisher handoff

`mobile_private_artifact.schema.json` defines the **11-key** immutable JSON passed
as `x` to `mobile_release.advertise(x jsonb)`. This candidate replaces that function
without editing the existing migration. It retains reserve/allocate, signer,
monotonic-floor, immutable receipt and pause/revocation guards. The key MUST be
`com.firesideafrica.firesidegroup/{version_code}/{commit}/{sha256}.apk`;
`tag` MUST equal `v{version_name}`. No `apk_url`, signed URL or expiry is stored.
The artifact receipt remains exactly the publisher's credential-free JSON.

Publisher integration is now implemented under explicit `MOBILE_REGISTRY_CONTRACT=mobile_release_private_v1` paired with native Supabase REST. Parent independently reran95 release-tool tests with actual PostgreSQL and no skips. Private receipts contain only these11 fields; create-only upload and exact readback precede advertisement. Mixed modes refuse before locks/reservation/cloud writes. Private GitHub drafts intentionally remain unpublished pending approved bootstrap distribution; no unusable public/signed URL is invented for legacy clients. Installed SQL, scoped credentials and live activation remain unverified.

## Phone/server protocol

- `POST /functions/v1/mobile-update`, JSON body exactly `{}`, with current employee
  Supabase access token (SDK-managed). No subject/email/PI/locator in input.
- 200 `{ "release": null }` when paused/revoked/no current artifact.
- 200 `{ "release": { ...11 immutable fields, "download_url": "https://supabase.firesideafrica.cloud/storage/v1/object/sign/fireside-mobile-releases/{object_key}?token=...", "expires_at": "UTC ISO8601" } }`.
- Signed delivery TTL is 60 seconds. All responses `no-store`. Auth failure 401/403;
  change during signing 409; backend/offline/malformed provider response 503.
  No provider exception, directory row, auth subject/email or credentials returned.
- Edge route validates token with live `/auth/v1/user`, then calls server-only
  `public.mobile_update_authorize(subject uuid)` using server configuration.
  It repeats BOTH after signing and compares immutable artifact fields.
- RPC re-resolves actual `auth.users` (verified email, nonanonymous, not deleted
  or banned) and requires one normalized email match across ALL Auth and PI rows,
  with PI active=true, deleted_at null, no effective resignation. User metadata,
  app role claims and public.users directory presence are not authority.
- Dart `SupabaseUpdateRegistry` invokes only this Edge function and refuses old
  public-contract responses. It attaches a local noncredential identity epoch,
  invalidated by logout/account switch. `AppUpdateService` compares stable
  identity before download/install, uses the refreshed URL (never compares
  rotating URLs), blocks redirect following, binds exact host/path, validates
  byte size/hash, and rechecks after installer permission await. Cache entries
  cannot bypass current authorization. Authenticated checks bypass legacy cooldown.
- Construct private service with `SupabaseUpdateRegistry(client)` and
  `AppUpdateConfig(storageBase:'https://supabase.firesideafrica.cloud/storage/v1')`.
  Default legacy updater wiring is deliberately NOT changed. Private opt-in must
  not fallback to GitHub after a private authorization/network failure.

## Candidate review/activation gates

Read-only catalog discovery confirmed `auth.users` and
`fireside_pi.personal_information` lifecycle columns, both RLS-enabled. SQL adds
column-only SELECT plus server-owner-only SELECT policies on those two base
relations; inactive/deleted duplicates remain visible for ambiguity rejection.
No employee/anon policy, BYPASSRLS, password/token column access or existing ACL
revocation is added. Server-only RPC removes inherited creator default EXECUTE
grants and grants only `service_role`. Existing shared-directory exposure is not
remediated or claimed safe by this additive candidate. Owner approval is required
for these new read grants/policies and coordinated function replacement.

Edge uses existing server-only `SUPABASE_SERVICE_ROLE_KEY`; this is broad server
signing authority, NOT scoped publisher authority. Never copy it to phone/CI.
Dedicated signer authority, effective memberships/default ACL review, gateway
per-subject rate limits, gateway Auth routing, normal TLS, Storage private policies,
server URL wiring, capacity and actual upload/install remain activation gates.
No JWT minted, secret inspected, production SQL mutation, deploy, commit or push.
Parent installed Deno tooling via its npm distribution and verified Deno2.9.6 type-check of the actual index.ts entrypoint. An actual Deno import with intercepted serve registration and synthetic server configuration exercised GET405 and unauthenticated POST401/no-store without production network. Full shared route logic executes in Node with hermetic Auth/RPC/Storage transports; the deployed Supabase Edge Runtime image/gateway remain untested. SQL executes against disposable real PostgreSQL17, with RLS and poisoned creator defaults. These prove local logic, not live deployment.

A signed URL is a bearer capability valid until its short expiry; a revocation
cannot invalidate an already-issued URL or retract already-delivered bytes.
Rechecks close local cached/install bypasses but cannot eliminate every race
between final authorization and Android installer handoff. Device installation
and fleet acceptance remain separate.

## Reproduce

```
node --test supabase/tests/private_delivery/handler_test.mjs
/usr/bin/python3 -m unittest discover -s supabase/tests/private_delivery -p test_sql.py -v
/home/nderitu/.hermes/cache/scratch/flutter-3.47.4/bin/flutter test --no-pub
/home/nderitu/.hermes/cache/scratch/flutter-3.47.4/bin/flutter analyze --no-pub
```

Python uses the existing disposable PG17 fixture/server binaries, Unix socket
only, synthetic Auth/PI/artifacts, no dotenv/network database. System Python has
psycopg; Hermes's default Python does not. No production data values are read.
