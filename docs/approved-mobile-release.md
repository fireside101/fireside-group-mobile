# Approved normal mobile release

## Authorization and release contract

Owner explicitly approved this release independently of Scoreboard, including
public latest/current/future APK publication for successful approved main builds.
No second test update may be published until the owner confirms the first fixed
APK was manually installed over the existing app with login/data retained.
No uninstall, package change, signer change or bypass is permitted.

Normal approved main releases now finalize stable GitHub latest only after exact
APK/signature/package/version, immutable private Storage bytes and private registry
receipt/current pointer verification. Public visibility is explicitly admitted by
`MOBILE_PUBLIC_RELEASE_APPROVED=true`; original/rerun actor remains josephndex,
current main and protected environment admission remain enforced. `update.json`
remains an integrity receipt without a public or signed URL, not a legacy feed.
Explicit historical bootstrap dispatch retains non-latest prerelease semantics.

## Application fixes

- Archive parsing requests GET_SIGNATURES together with GET_SIGNING_CERTIFICATES
  on modern Android, while installed lookup/current signer equality stays strict.
  Actual framework parser tests include signed and tampered APKs; disposable test
  fixtures are committed, with no production key.
- Production portal profile uses the existing authenticated `/api/profile`
  rich GET `{details,options,avatarUrl}` / PATCH `{details}` contract. Names retain
  First, Last, Third order and 80-character limits, omitted/null/empty semantics,
  server-response refresh, rich editors/avatar/password and per-user cache.
- Production TBT targets the existing PTW origin and mobile SSO gateway, then the
  explicit unified `/?source=tbt` landing. Historical PTW source remains intact.
  DEV requires all reviewed defines and remains separate from production trust.
- CI first-party actions use upstream-verified Node24 majors on Ubuntu24.04;
  Node22 application tests and Java17/Flutter3.47.4 remain explicit. Native host
  installer/archive tests run before retained production artifact admission.

## Local verification before release

- Flutter analyze: no issues. Full serial Flutter suite: **152 passed**.
- Publisher suite with real isolated PostgreSQL17.6: **162 passed, no skips**.
  Updated historical draft/private retry expectations to distinguish explicit
  bootstrap prereleases from normal stable private-backed releases.
- Workflow YAML and 30 bash blocks parsed successfully; upstream action.yml
  runtimes independently read back as node24 for all six used action families.
- Native isolated source/fixtures compared byte-for-byte with this checkout.
  Full native suite: **97 passed, zero failures/errors/skips**; test APK compiled.
  Real production v1.0.9/v1.0.10 framework archive suite: **6 passed**.
  Hosted/publication verification will be recorded after completion.
- Live production portal API, TBT health and mobile Edge deployment: HTTP200;
  registry currently v1.0.10/code10 and private bucket remains nonpublic/200MB.

Phone acceptance is NOT established by host tests or successful publication.
The installed faulty updater may refuse its own fix. Deliver the verified fixed
higher APK for browser/Files install-over, then await owner confirmation of
retained login/data before publishing a second test update.
