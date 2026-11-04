# TBT catalogue and PI third-name mobile follow-up

> Release supersession: compatible portal/TBT backends are now deployed and the
> owner authorized production mobile release. Production profile requests are
> enabled only for the exact reviewed portal origin; production TBT opens
> `https://ptw.firesideafrica.cloud/?source=tbt` after the existing mobile SSO.
> The source-only/production-held statements below describe the earlier DEV
> implementation checkpoint, not the current release decision. Current gates
> and release handles are recorded in `approved-mobile-release.md`.

> Final contract alignment: this document's earlier local-web discovery is
> superseded by the actual integrated DEV source described below. No live
> persistence or production readiness is claimed.

## Scope and audit

DEV-first source-only follow-up. No commits, pushes, releases, workflow dispatches,
Android/CI changes, production configuration changes, or live profile writes.
Read the BI `START-HERE.md`, workspace skill registry, Flutter patterns and TDD
instructions before implementation.

Already solved and deliberately retained: installed-package version/build labels;
authenticated `/api/profile` client and editable PI profile screen; shared profile
cache and server-response propagation; stable ID-based recent apps; approved PTW
WebView/mobile SSO and camera-origin restrictions; secure auth/private update
infrastructure. No replacement storage, identity API or update path was added.

## Catalogue compatibility

The bundled `attendance-ptw` entry now displays **TBT**. Its ID, repository,
category, URL `https://ptw.firesideafrica.cloud/`, health URL `/healthz`, icon,
WebView policy, mobile SSO gateway and persisted preferences remain unchanged.
Search supports both TBT/toolbox talks and Attendance PTW/attendance/permits.
Existing application navigation uses this URL, not an invented `/tbt` endpoint.
The active authenticated TBT landing page remains a DEV/device acceptance check;
this source-only change does not claim a live login or active-session verification.

## Existing mobile API contract (not a newly invented endpoint)

`ProfileService` uses explicit `MobileTargets` modes. Default production catalogue
selection is retained, but **all production profile HTTP remains gated pending
compatible backend deployment and separate approval**. DEV requires the existing
three reviewed defines together: `MOBILE_DEPLOYMENT_ENV=development`,
`TBT_BASE_URL=https://ptwdev.firesideafrica.cloud`, and
`PORTAL_API_BASE_URL=https://firesidegroupdev.firesideafrica.cloud`.
A URL override cannot enable production profile writes. Future approved production
support must use the existing actual portal API
`https://firesidegroup.firesideafrica.cloud/api/profile`, not a parallel identity
endpoint; no production-enabling flag or fallback is introduced here.
`MobileTargets` configuration/approved catalogue were not changed.

Actual current API:

- GET `/api/profile`, current Supabase session `Authorization: Bearer …`.
- Response `{details, options, avatarUrl}`. `details` contains `fullName`,
  `department`, `fields: [{label,value}]`, and `editable`.
- PATCH `/api/profile`, same authentication and JSON editable fields, returning
  `{details: <updated PersonalDetails>}`. The response, not a local-only name,
  updates the existing shared profile cache and profile/home/header consumers.
- `editable.first_name`, `editable.last_name`, `editable.third_name`; current
  `third_name` is a STRING, `""` when absent in PI. Legacy nullable decoding is
  retained. Editor/PI display order is **First name → Last name → Third name**;
  `details.fullName` remains authoritative. All three names enforce 80 characters
  before save. Backend retains syntax, identity and eligibility validation.
- A missing name key stays absent through parse/cache/PATCH and is not offered
  for editing. Explicit null and empty third_name remain distinct; unrelated
  saves preserve them. Unicode is retained. No splitting of a full name.
- No `id`, `person_id`, `staff_email`, user ID or arbitrary target parameter can
  be supplied by the typed editable model. The backend must derive PI identity
  from verified auth and authorize that identity; client tests are not proof of
  server-side cross-person protection.
- Existing avatar/password endpoints and authentication behavior are unchanged.
  An optional `SupabaseClient` constructor dependency enables isolated service
  tests; runtime still uses the existing singleton by default.

### Contract blocker / web handoff

Read-only inspection of the ACTUAL integrated DEV checkout
`/home/nderitu/work/firesidegroup-tbt-dev-integration` supersedes the stale checkout
inspection: `docs/dev-integration-review.md`, `src/app/api/profile/route.ts`,
`src/lib/pi-profile.ts`, `src/types/profile.ts`. The installed contract is rich
GET `{details, options, avatarUrl}` and PATCH `{details}`, NOT `{profile}`.
The secondary names-only adapter is compatibility-only and does not hide current
rich editors/photo/password or change current PATCH behavior.

Current rich saves remain full-personal updates; backend additionally accepts
name-only subsets without making every partial personal update valid. Omitted
name keys are preserved. Identity is server-derived from confirmed Auth email,
required-password status, a unique active/nondeleted case-insensitive PI match,
and linked app-metadata ID agreement. API responses are `Cache-Control: no-store`;
existing per-user secure mobile cache remains unchanged. Successful PATCH uses
server details while preserving options/avatar/rich capabilities. Denied saves
leave shared details unchanged. Client tests do not prove server authorization.

Exact representative synthetic JSON fixtures are in
`test/fixtures/profile/{get,patch,patch_clear}.json`. Envelope keys were read from
the actual route; all three details bodies were structurally compared with output
from the ACTUAL integrated `toDetails` serializer, transpiled read-only with
TypeScript and a throwing Supabase provider stub: **3 comparisons passed**.
Scratch checker: `/home/nderitu/.hermes/cache/scratch/verify-mobile-profile-fixtures.cjs`.
These are offline source-derived fixtures, NOT captured or fabricated live results.
`test/data/current_profile_contract_test.dart` exercises them through real service
GET/PATCH decoding, bearer auth, full editable payload, Unicode edit, string-empty
clear, omitted-third preservation, secure-cache JSON roundtrip, shared response
refresh, rich capabilities/options/avatar preservation, 401/403/409/500 propagation,
DEV target rejection and default production gate.

Local mobile contract alignment is verified; no further envelope/order/limit
inference is needed. Deployed DEV revision/schema, approved live own-record
read/save/readback (DEV shares PI with production), installed-device SSO/camera/
upload/session survival and production publication remain separate gates.
No web, Android, CI or MobileTargets config files were edited by this final pass.

No direct PI database or live mutation was used. PI schema detail supplied by
the task: `third_name text NULL` alongside `first_name`, `last_name`,
`staff_email`, `id`.

## TDD and verification

New tests were run before their implementation and exposed missing model/form
behavior and the old Attendance PTW display name. The real profile widget also
exposed Flutter 3.47.4's ListTile/DecoratedBox assertion; profile cards now give
children a transparent Material ancestor without changing their decoration.
Widget tests use bounded pumps (text input cursors keep scheduling frames).

Toolchain: scratch `flutter-3.47.4`, Flutter 3.47.4 / Dart 3.13.3.

- `flutter analyze`: **No issues found**.
- Final focused profile/target/model/widget run: **26 passed**.
- Explicit DEV-compiled target/security/current-contract run (all three reviewed
  defines): **11 passed**.
- Final `flutter test --concurrency=1 --timeout=2m`: **151 passed**.
- Final `flutter analyze`: **No issues found** (one initial test-only braces lint
  was corrected; focused fixture tests reran successfully afterward).
- Final full-suite log: `/home/nderitu/.hermes/cache/scratch/mobile-current-profile-full-tests.log`.
- Initial default-concurrency full run: 135 passed, one unrelated existing APK
  loopback download timeout (`small complete 200 remains compatible without
  range validators`). No update code/tests were changed. The serial full rerun
  above passed, including that exact test.
- `git diff --check`: clean.
- Coverage includes catalogue identity/URL/legacy search, nullable/empty/missing
  names, Unicode round trips, identity-field exclusion, authenticated exact
  GET/PATCH contract, signed-out refusal before HTTP, server 403 propagation,
  form order/save, null/empty preservation, older-contract omission and shared
  post-save home greeting refresh. Existing version, SSO and update tests pass.

## Files owned by this follow-up

- `lib/data/models/profile_details.dart`
- `lib/data/repositories/local_catalogue_repository.dart`
- `lib/data/services/profile_service.dart`
- `lib/features/home/widgets/hero_section.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/shell/app_header.dart` (name initial only; version tag untouched)
- `test/data/tbt_profile_contract_test.dart`
- `test/data/profile_service_test.dart`
- `test/data/current_profile_contract_test.dart`
- `test/fixtures/profile/get.json`
- `test/fixtures/profile/patch.json`
- `test/fixtures/profile/patch_clear.json`
- `test/features/profile_third_name_test.dart`
- `docs/tbt-profile-mobile-followup.md`
