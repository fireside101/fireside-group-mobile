# Explicit mobile DEV targets — local configuration only

> Current release supersession: production is now explicitly authorized after
> backend deployment. Production accepts only the exact reviewed TBT/portal
> origins (optionally one trailing slash), and profile HTTP is enabled with
> authenticated identity. DEV still requires all three defines and cannot trust
> production origins. Earlier held/source-only claims below are historical;
> see `approved-mobile-release.md` for the current verification boundary.

## Reviewed targets

No existing Dart app/build flavor selector was found. `MobileTargets` adds a
build-time target selector, **not** a new app identity or Android flavor.

The reviewed TBT browser origin is **https://ptwdev.firesideafrica.cloud**, from
`attendance-modernization/frontend/deploy-dev/ingressroute-tls.yaml` (exact Host
rule). `frontend/nginx.conf.template` maps that host's `/api/` and exact
`/auth/fireside/mobile` to `ptw-api.ptw-api-staging.svc.cluster.local`, with upstream
Host `ptwapidev.firesideafrica.cloud`. The API hostname itself is **not** an
approved mobile browser/native origin. These are source observations, not proof
of the live installed deployment or its database isolation.

## Required DEV defines

Supply all three together to the existing Flutter command; no credentials are
included here:

```text
--dart-define=MOBILE_DEPLOYMENT_ENV=development
--dart-define=TBT_BASE_URL=https://ptwdev.firesideafrica.cloud
--dart-define=PORTAL_API_BASE_URL=https://firesidegroupdev.firesideafrica.cloud
```

The two URLs accept only these exact strings, optionally with one trailing `/`.
Other hosts, credentials, ports (including an explicit `:443`), paths, query,
fragment, whitespace, production targets, missing settings and unknown modes are
rejected. There is no debug/release inference, remote allowlist or production
fallback. A portal DEV define without the explicit DEV mode and TBT URL fails
catalogue/security initialization rather than leaving a production TBT tile.

With no defines, the default production catalogue is preserved. The production
mode does not accept target overrides (including a nonempty
`PORTAL_API_BASE_URL`). Production profile APIs remain disabled by the existing
`ProfileService`; this change does not make them ready or enable them. Runtime
`SUPABASE_URL` / `SUPABASE_ANON_KEY` must separately match the authorized DEV
identity provider; no values were read or changed here.

## Preserved contracts

- Only the URL and health URL of stable ID `attendance-ptw` change in DEV; its
  repository, favourites/recents keys and other catalogue entries do not change.
  Other app tiles **still point to their existing targets**; this is not a
  whole-catalogue DEV migration.
- Bearer admission and native bridge trust use the same selected, bundled origin.
  DEV rejects the production PTW origin, even after navigation. HTTPS default
  origin port 443 remains required at runtime; native capabilities, frame-origin
  checks, request replay protection, logout and navigation lease invalidation
  are retained.
- Gateway remains `/auth/fireside/mobile`; PTW source resolves the validated
  bearer email to an active local user, establishes its browser session and
  redirects to `/`. No token-in-query, invented `next` parameter, email override,
  or production retry is added. Unified landing is a subsequent cookie-only
  `/?source=tbt` navigation. Explicit historical `source=ptw`, non-root routes
  and login/failure routes are not rewritten.
- App/package identity, session storage, preferences, Android, workflow and
  profile-service code were not changed by this task.

## Local verification

Red first: running the compile-defined DEV tests against the previous code
failed all three assertions (production catalogue, production-only origin
policy, missing DEV unified landing). After implementation:

```sh
flutter test --no-pub --reporter expanded
flutter test --no-pub --reporter expanded \
  --dart-define=MOBILE_DEPLOYMENT_ENV=development \
  --dart-define=TBT_BASE_URL=https://ptwdev.firesideafrica.cloud \
  --dart-define=PORTAL_API_BASE_URL=https://firesidegroupdev.firesideafrica.cloud \
  test/data/mobile_targets_test.dart test/data/mobile_targets_security_test.dart
flutter analyze --no-pub
git diff --check
```

Default full suite: **147 passed**. Explicit DEV configuration/security run:
**8 passed**. Analysis: **No issues found**. Tests are synthetic/local and do not
request live TBT/profile endpoints. Older production-specific regression tests
are exercised by the default full suite, not misrepresented as a full DEV run.

## Gates still open — no live writes authorized

1. Parent must inspect installed DEV ingress/proxy revision and API/DB/media
   routing before authenticating or capturing anything. The checked-in staging
   config references the production database TLS setup and production status
   reads; a DEV hostname alone does **not** establish isolated data. Even SSO
   calls `touch_last_login`. Do not perform login/capture against production or
   assume this source configuration proves zero production-backed writes.
2. Confirm approved DEV identity-provider settings and compatible installed
   profile/TBT contracts. The portal profile path can share PI data; writes are
   real and require separate owner approval and controlled records.
3. Verify native device SSO/cookies, email identity, camera, uploads, remembered
   teams, historical source views, update/install and reopen/session survival
   separately. No device test, artifact build/publication, deployment, commit,
   push or live write was performed here. Production publication remains held.
