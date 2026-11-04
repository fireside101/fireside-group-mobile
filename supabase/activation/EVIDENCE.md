# Local activation evidence

- Rehearsed server binary: PostgreSQL **17.6** at `/home/nderitu/.hermes/cache/scratch/unified-attendance-pg17/pgsql/bin`.
- Client environment: `/home/nderitu/.hermes/cache/scratch/mobile-transport-venv/bin/python`, psycopg **3.3.8**, libpq **180006**. Activation pins psycopg 3.3.8 separately; the existing publisher's 3.3.7 requirements were not modified.
- Gate: `python -m unittest discover -s supabase/tests/activation -v` using that interpreter: **9 tests, OK, zero skips**.
- Real owner wrapper `run()` was exercised for install and refresh against synthetic PG17 over verify-full TLS/SCRAM, with only target admission and secure-input source substituted. Correct password accepted; wrong password, previous rotated password, expired password, and certificate-hostname mismatch refused. Generated raw passwords were absent from the disposable PostgreSQL log. Output directory/file mode assertions passed.
- Combined exact SQL (the UTF-8 bytes returned by `activate.combined()`, transaction controlled by the wrapper): SHA-256 `867be12e13ebdf9009a44c885cb136b1c671ebe172249a367e019fc53dca5ad4`.
- Every constituent SQL hash, including `verify.sql`, is recorded in `sha256.json` and checked before network IO. `verify.sql` is executed separately before commit and after exact-target readback; the dynamic password SCRAM verifier/expiry are intentionally not static SQL.
- CLI argument/help parsing was exercised. The production command was **not** executed; there was no production SQL/role/credential issuance and no production secret was read or created by this local package.

## Verified local boundaries

Fresh roles only; atomic rollback on existing-role/default-ACL/column-ACL/public-definer/policy collision; complete owner/executor matrix; drift refusal for memberships, owners, column grants, Storage RLS and restrictive fences; paused known-published seed; scoped registry LOGIN negatives; private publication and Auth/PI authorization flow; no anonymous authorization RPC; finite JWT claims; secure input-FD mode checks; actual TLS/password rotation and private output.

## Live read-only preparation

Supabase MCP catalog reads observed database `postgres`, server 17.6, no `mobile_release%` roles or schema, private bucket `fireside-mobile-releases` with 200000000-byte limit, no PUBLIC Storage column grants or PUBLIC-definer routines, no PUBLIC identity-definer routines, and no PUBLIC CREATE on public/auth/fireside_pi/storage. Source public-schema function defaults include other executors; the isolated fixture poisons defaults and demonstrates the new authorization RPC does not retain them.

Read-only catalogs are not SQL installation, Storage gateway custom-role acceptance, deployed Edge acceptance, versioned secret delivery, installed-fleet census, or device upgrade evidence. Those remain the explicit bootstrap/acceptance requirements in README.md. All disposable clusters were task-owned; no shared 55479 lifecycle operation was performed.
