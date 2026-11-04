#!/usr/bin/env python3
"""Owner-run DB bootstrap. No deployment, GitHub writes, or activation/unpause.
Input is a private regular file on stdin; credentials never belong in argv/env.
"""
import argparse
import base64
import datetime as dt
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import stat
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCES = ['supabase/activation/preflight.sql',
           'supabase/migrations/202611030001_mobile_release.sql',
           'supabase/migrations/202611040001_mobile_release_storage_authority.sql',
           'supabase/candidates/mobile_private_delivery.sql',
           'supabase/activation/finalize.sql']

def combined():
    manifest = json.loads((HERE / 'sha256.json').read_text())
    parts = []
    for name in SOURCES + ['supabase/activation/verify.sql']:
        raw = (ROOT / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != manifest[name]:
            raise ValueError('SQL source hash mismatch')
        if name not in SOURCES:
            continue
        # Existing candidate transaction markers are standalone. One outer
        # transaction prevents storage-policy failure leaving registry installed.
        text = '\n'.join(line for line in raw.decode().splitlines()
                         if line.strip() not in ('BEGIN;', 'COMMIT;'))
        parts.append(text)
        parts.append('RESET ROLE; SET LOCAL search_path=pg_catalog;')
    return '\n'.join(parts)


def jwt_token(key, now=None):
    now = int(time.time()) if now is None else now
    enc = lambda x: base64.urlsafe_b64encode(x).rstrip(b'=')
    head = enc(b'{"alg":"HS256","typ":"JWT"}')
    body = enc(json.dumps({'role': 'mobile_release_storage_publisher',
        'sub': '00000000-0000-4000-8000-000000000001', 'aud': 'authenticated',
        'iss': 'supabase', 'iat': now, 'nbf': now, 'exp': now + 3600},
        separators=(',', ':')).encode())
    message = head + b'.' + body
    return (message + b'.' + enc(hmac.new(key.encode(), message, hashlib.sha256).digest())).decode()


def scram(password):
    salt = secrets.token_bytes(16)
    iterations = 4096
    salted = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, iterations)
    client = hmac.new(salted, b'Client Key', hashlib.sha256).digest()
    stored = hashlib.sha256(client).digest()
    server = hmac.new(salted, b'Server Key', hashlib.sha256).digest()
    enc = lambda b: base64.b64encode(b).decode()
    return f'SCRAM-SHA-256${iterations}:{enc(salt)}${enc(stored)}:{enc(server)}'


def private_input(fd=0):
    s = os.fstat(fd)
    if not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid() or stat.S_IMODE(s.st_mode) != 0o600:
        raise ValueError('stdin must be an owner-owned mode0600 regular file')
    with os.fdopen(os.dup(fd)) as stream:
        value = json.load(stream)
    if set(value) != {'owner_dsn', 'jwt_secret'} or len(value['jwt_secret']) < 32:
        raise ValueError('invalid private owner input')
    return value


def owner_options(dsn):
    from psycopg.conninfo import conninfo_to_dict
    info = conninfo_to_dict(dsn)
    # Forbid inherited libpq routing/services/options and credential overrides.
    if any(k.startswith('PG') for k in os.environ):
        raise ValueError('clear inherited PG* environment')
    allowed = {'host','port','dbname','user','password','sslmode','sslrootcert','connect_timeout'}
    if set(info) - allowed or info.get('host') != 'supabase.firesideafrica.cloud' or info.get('port') != '5433' or info.get('dbname') != 'postgres' or info.get('sslmode') != 'verify-full':
        raise ValueError('explicit production verified-TLS target required')
    ca = Path(str(info.get('sslrootcert', '')))
    if not ca.is_absolute() or not ca.is_file() or not info.get('password') or not info.get('user'):
        raise ValueError('owner credential and absolute CA path required')
    info['connect_timeout'] = '10'
    return info


def run(args):
    import psycopg
    from psycopg import sql
    from psycopg.conninfo import make_conninfo
    bundle = combined()  # hashes checked before credentials or network
    value = private_input()
    info = owner_options(value['owner_dsn'])
    out = Path(args.output).resolve()
    # Never emit even narrow credentials inside this checkout.
    if out == ROOT or ROOT in out.parents or not out.parent.is_dir():
        raise ValueError('private output must be outside checkout under existing parent')
    sealed = False
    for parent in reversed(out.parents):
        meta = parent.stat()
        mode = stat.S_IMODE(meta.st_mode)
        if meta.st_uid not in (0, os.getuid()) or (not sealed and mode & 0o022):
            raise ValueError('unsafe output ancestor custody')
        # A private owner-only ancestor makes otherwise group-writable cache
        # descendants unreachable to other UIDs; do not repair their modes.
        sealed = sealed or (meta.st_uid == os.getuid() and mode == 0o700)
    if stat.S_IMODE(out.parent.stat().st_mode) != 0o700:
        raise ValueError('output parent must be private mode0700')
    out.mkdir(mode=0o700, exist_ok=False)
    password = secrets.token_urlsafe(48)
    expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=24)
    # Raw password never appears in SQL, server statement logs or errors.
    verifier = scram(password)
    with psycopg.connect(make_conninfo(**info)) as conn:
        conn.execute("SET LOCAL statement_timeout='60s'; SET LOCAL lock_timeout='5s'")
        if conn.execute('SELECT current_database(),current_setting(\'server_version_num\')::integer/10000').fetchone() != ('postgres',17):
            raise ValueError('target attestation failed')
        if args.action == 'install-paused':
            conn.execute(sql.SQL(bundle))
        # Same exact catalog admission before commit and before every refresh.
        conn.execute(sql.SQL((HERE / 'verify.sql').read_text()))
        conn.execute(sql.SQL('ALTER ROLE mobile_release_registry_login PASSWORD {} VALID UNTIL {}').format(sql.Literal(verifier),sql.Literal(expires.isoformat())))
    narrow = dict(info, user='mobile_release_registry_login', password=password)
    # Independent exact-target readback as actual new LOGIN, including pg_stat_ssl.
    with psycopg.connect(make_conninfo(**narrow)) as conn:
        row = conn.execute("SELECT current_user,ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()").fetchone()
        if row != ('mobile_release_registry_login', True):
            raise ValueError('dedicated TLS login verification failed')
        conn.execute('SELECT mobile_release.latest()')
    with psycopg.connect(make_conninfo(**info)) as conn:
        conn.execute(sql.SQL((HERE / 'verify.sql').read_text()))
    payload = {'MOBILE_REGISTRY_DSN': make_conninfo(**narrow),
        'MOBILE_SUPABASE_STORAGE_TOKEN': jwt_token(value['jwt_secret']),
        'MOBILE_REGISTRY_CONTRACT':'mobile_release_private_v1',
        'MOBILE_STORAGE_PROVIDER':'supabase-rest',
        'MOBILE_SUPABASE_STORAGE_ENDPOINT':'https://supabase.firesideafrica.cloud',
        'MOBILE_SUPABASE_STORAGE_BUCKET':'fireside-mobile-releases'}
    # Create-only output, never stdout. Secure issuer input is not copied.
    fd = os.open(out / 'publisher.json', os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
    with os.fdopen(fd,'w') as f:
        json.dump(payload,f); f.flush(); os.fsync(f.fileno())
    (out / 'receipt.json').write_text(json.dumps({'state':'DB_INSTALLED_PAUSED' if args.action=='install-paused' else 'CREDENTIALS_REFRESHED',
        'storage_expires_in_seconds':3600,'registry_expires_at':expires.isoformat(),
        'deployment':'NOT_PERFORMED','gateway_custom_role':'UNVERIFIED','fleet_max':'UNKNOWN'}))
    os.chmod(out / 'receipt.json',0o600)
    print('Private credential files written; deployment and live transport remain held.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['install-paused','refresh'])
    parser.add_argument('--output',required=True)
    parser.add_argument('--owner-approved',action='store_true',required=True)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        run(args)
    except Exception:
        # Never echo libpq errors/SQL, DSNs or arbitrary server data.
        print('REFUSED or outcome UNKNOWN: inspect private owner-side state; do not blindly replay.',file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
