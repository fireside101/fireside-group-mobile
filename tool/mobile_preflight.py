#!/usr/bin/env python3
"""Manual scoped production proof only. Never allocate, publish, sign or unpause.

The only attempted remote mutation is a create-only POST to one already-read
verification object; never a new key, upsert, SQL write or publication API.
"""
import base64
import hashlib
import json
import os
import re
import sys
import time
from urllib.parse import quote

import mobile_release as release

ORIGIN = 'https://supabase.firesideafrica.cloud'
APK_SHA = 'f9ccf634e845efe981aeb2996b8e36087a83a986e85c4b9842832d6061fe7a49'
APK_SIZE = 58983786
KEY = '_verification/published-v1.0.4-' + APK_SHA + '.apk'
EDGE_SOURCE = '985a2815641f1770c285e1b82995dbb4abd682bc'
EDGE_HANDLER = '4f98c3d34a98c989ecb4995ae65e63937540e7bc3b3ea244a24bee1c105f15e5'
require = release.require


def admit(env):
    require(env.get('GITHUB_ACTOR') == 'josephndex'
            and env.get('GITHUB_TRIGGERING_ACTOR') == 'josephndex'
            and env.get('GITHUB_REF') == 'refs/heads/main'
            and env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and env.get('GITHUB_REPOSITORY') == release.REPOSITORY,
            'runtime_admission_held')


def check_token(token):
    # This is only a local scope/expiry sanity check, NOT signature attestation.
    # Real authenticated Storage GET proves backend acceptance separately.
    require(isinstance(token, str) and len(token) <= 8192, 'token_scope_held')
    parts = token.split('.')
    require(len(parts) == 3, 'token_scope_held')
    header, claims = [json.loads(base64.urlsafe_b64decode(p + '=' * (-len(p) % 4)))
                      for p in parts[:2]]
    now = int(time.time())
    require(header.get('alg') == 'HS256' and claims.get('role') == 'mobile_release_storage_publisher'
            and type(claims.get('iat')) is int and type(claims.get('exp')) is int
            and now - 3600 <= claims['iat'] <= now + 30
            and now + 120 < claims['exp'] <= claims['iat'] + 3600,
            'token_scope_held')


class ProbeStorage(release.SupabaseStorage):
    """Existing native adapter plus mandatory range/size/ETag evidence."""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.snapshot_etag = None
        self.range_count = 0

    def _curl_request(self, url, headers, data, **kwargs):
        status, body, response = super()._curl_request(url, headers, data, **kwargs)
        if 'Range' in headers and 'Authorization' in headers:
            require(status == 206 and response.get('content-range', '').endswith('/' + str(APK_SIZE)),
                    'range_proof_held')
            etag = response.get('etag', '')
            require(re.fullmatch(r'"[\x21\x23-\x7e]+"', etag) is not None, 'range_proof_held')
            require(self.snapshot_etag in (None, etag), 'snapshot_changed')
            self.snapshot_etag = etag
            self.range_count += 1
        return status, body, response


def probe_storage(storage):
    # Never expose a key argument: even test fixtures use this exact target.
    before = storage.read(KEY)
    require(len(before) == APK_SIZE and hashlib.sha256(before).hexdigest() == APK_SHA,
            'baseline_mismatch')
    target = f'{storage.endpoint}/object/{storage.bucket}/{quote(KEY, safe="/")}'
    anonymous, _, _ = storage._curl_request(target, {'Range': 'bytes=0-0'}, None,
                                           method='GET', max_size=4096)
    require(anonymous in (401, 403, 404), 'anonymous_read_not_denied')
    # Replay only the exact verified original bytes to the exact existing key,
    # create-only. Never use a destructive sentinel or attempt a new object.
    # Finally-read runs even for a transport failure: uncertain POST is never retried.
    try:
        status, body = storage._request('POST', KEY, before)
    finally:
        after = storage.read(KEY)
        require(after == before, 'original_bytes_changed')
    require(status in (400, 403, 409) and len(body) <= 4096, 'duplicate_not_denied')
    envelope = json.loads(body)
    require(isinstance(envelope, dict), 'duplicate_envelope_held')
    code = str(envelope.get('statusCode', ''))
    require((status == 403 and code == '403')
            or (status in (400, 409) and code == '409' and envelope.get('error') == 'Duplicate'),
            'duplicate_envelope_held')
    return dict(authenticated_native_rest=True, bounded_ranges=storage.range_count,
                strong_etag=True, total_bytes=APK_SIZE, sha256=APK_SHA,
                exact_bytes_unchanged=True, duplicate_post_status=status,
                anonymous_get_status=anonymous)


def probe_sql(env):
    import psycopg
    # Same private adapter and strict issuer CA path as actual publication.
    release.prepare_registry_ca(env)
    registry = release.PostgresRegistry.from_environment(env)
    with psycopg.connect(registry.dsn, connect_timeout=10,
                         options='-c default_transaction_read_only=on -c statement_timeout=30000') as conn:
        row = conn.execute("""SELECT current_user, session_user, r.rolcanlogin,
            r.rolsuper, r.rolbypassrls, r.rolcreatedb, r.rolcreaterole, r.rolreplication,
            (SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()),
            EXISTS(SELECT FROM pg_auth_members WHERE member=r.oid),
            has_function_privilege(current_user,'mobile_release.allocate(text,text,text)','EXECUTE'),
            has_function_privilege(current_user,'mobile_release.reserve(text,text,integer,text)','EXECUTE'),
            has_function_privilege(current_user,'mobile_release.advertise(jsonb)','EXECUTE'),
            has_function_privilege(current_user,'mobile_release.receipt(text)','EXECUTE'),
            has_function_privilege(current_user,'mobile_release.latest()','EXECUTE'),
            has_table_privilege(current_user,'mobile_release.app','SELECT,INSERT,UPDATE,DELETE'),
            has_any_column_privilege(current_user,'mobile_release.app','SELECT,INSERT,UPDATE'),
            has_function_privilege(current_user,'public.mobile_update_authorize(uuid)','EXECUTE')
            FROM pg_roles r WHERE r.rolname=current_user""").fetchone()
        require(row is not None and row[0] in ('mobile_release_ci_a', 'mobile_release_ci_b')
                and row == (row[0], row[0], True,
                            False, False, False, False, False, True, False,
                            True, True, True, True, True, False, False, False), 'sql_scope_held')
        # No base-table reads or writes. NULL alone cannot distinguish paused from
        # unpublished; do not claim an independent control-row/floor attestation.
        require(conn.execute('SELECT mobile_release.latest()').fetchone() == (None,),
                'latest_not_null')
    return dict(verify_full_tls=True, scoped_login=True, publisher_routines_allowed=True,
                latest_null=True, state='paused_or_unpublished', sql_writes=False)


def probe_health(storage):
    status, _, _ = storage._curl_request(ORIGIN + '/storage/v1/status', {}, None,
                                        method='GET', max_size=4096)
    require(status == 200, 'storage_health_held')
    status, body, _ = storage._curl_request(ORIGIN + '/functions/v1/mobile-update/_deployment',
                                           {}, None, method='GET', max_size=4096)
    require(status == 200 and json.loads(body) == dict(revision=EDGE_SOURCE, handler_sha256=EDGE_HANDLER),
            'edge_source_held')
    status, _, _ = storage._curl_request(ORIGIN + '/functions/v1/mobile-update',
        {'Content-Type': 'application/json'}, b'{}', method='POST', max_size=4096)
    require(status == 401, 'edge_unauthenticated_held')
    return dict(storage_status=200, edge_deployment_status=200,
                expected_source=True, edge_no_jwt_status=401)


def preflight(env):
    admit(env)
    # Actual GitHub metadata read, independent of the environment label. Approval
    # flags intentionally stay false; preflight does not grant publication consent.
    stage = 'environment'
    try:
        release.verify_environment()
        require(env.get('MOBILE_REGISTRY_CONTRACT') == release.PRIVATE_CONTRACT
                and env.get('MOBILE_STORAGE_PROVIDER') == 'supabase-rest'
                and env.get('MOBILE_SUPABASE_STORAGE_ENDPOINT') == ORIGIN + '/storage/v1'
                and env.get('MOBILE_SUPABASE_STORAGE_BUCKET') == release.PRIVATE_BUCKET,
                'private_configuration_held')
        stage = 'token'
        check_token(env.get('MOBILE_SUPABASE_STORAGE_TOKEN', ''))
        storage = ProbeStorage(env['MOBILE_SUPABASE_STORAGE_ENDPOINT'], release.PRIVATE_BUCKET,
                               env['MOBILE_SUPABASE_STORAGE_TOKEN'])
        stage = 'sql'
        sql = probe_sql(env)
        stage = 'health'
        health = probe_health(storage)
        stage = 'storage'
        storage_result = probe_storage(storage)
    except Exception:
        raise release.Held('preflight_' + stage + '_held') from None
    return dict(status='verified', protected_environment=True,
                credential_metadata='scope_and_expiry_only_not_signature_proof',
                sql=sql, health=health, storage=storage_result,
                employee_auth_pi_end_to_end='not_available', publication_enabled=False)


def main():
    try:
        result = preflight(os.environ)
        code = 0
    except Exception as exc:
        # Only fixed allowlisted stage labels; never arbitrary exception content.
        allowed = {'preflight_' + s + '_held' for s in ('environment', 'token', 'sql', 'health', 'storage')}
        error = str(exc) if isinstance(exc, release.Held) and str(exc) in allowed else 'preflight_held'
        result, code = dict(status='held', error=error,
                            employee_auth_pi_end_to_end='not_available', publication_enabled=False), 1
    print(json.dumps(result, sort_keys=True, separators=(',', ':')))
    return code


if __name__ == '__main__':
    sys.exit(main())
