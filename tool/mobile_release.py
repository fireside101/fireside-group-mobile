#!/usr/bin/env python3
"""Server-only Android promotion. No implicit credentials, schema or storage target.

Python stdlib core; production adapters require boto3 and psycopg[binary].
Never import this into Flutter or pass its environment via --dart-define.
"""
import argparse
from contextlib import contextmanager, nullcontext
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import tempfile
from urllib.parse import quote, urlsplit
from urllib.request import Request, HTTPRedirectHandler, ProxyHandler, build_opener
from urllib.error import HTTPError

PACKAGE = 'com.firesideafrica.firesidegroup'
REPOSITORY = 'fireside101/fireside-group-mobile'

class Held(RuntimeError):
    """Publication refused; errors intentionally contain no upstream response bodies."""

def require(condition, reason):
    if not condition:
        raise Held(reason)

def json_equal(left, right):
    # Python dict equality aliases bool/int/float; release receipts must not.
    return json.dumps(left, sort_keys=True, separators=(',', ':'), allow_nan=False) == json.dumps(
        right, sort_keys=True, separators=(',', ':'), allow_nan=False)


def safe_url(url):
    parsed = urlsplit(url)
    require(parsed.scheme == 'https' and parsed.hostname and not parsed.username
            and not parsed.password and not parsed.query and not parsed.fragment,
            'approved HTTPS storage URL required (no credentials/query/fragment)')
    return url.rstrip('/')

@dataclass(frozen=True)
class Spec:
    version: str
    code: int
    commit: str
    signer: str

    def __post_init__(self):
        require(bool(re.fullmatch(r'\d+\.\d+\.\d+', self.version)), 'invalid version')
        require(type(self.code) is int and 0 < self.code <= 2100000000, 'invalid versionCode')
        require(bool(re.fullmatch('[0-9a-f]{40}', self.commit)), 'full source commit required')
        require(bool(re.fullmatch('[0-9a-f]{64}', self.signer)), 'verified production signer required')

    @property
    def tag(self): return 'v' + self.version
    @property
    def apk_name(self): return f'fireside-group-{self.tag}.apk'
    def object_key(self, digest):
        return f'{PACKAGE}/{self.code}/{self.commit}/{digest}.apk'


PRIVATE_CONTRACT = 'mobile_release_private_v1'
PUBLIC_CONTRACT = 'mobile_release_v1'
PRIVATE_BUCKET = 'fireside-mobile-releases'


def check_contract_environment(env):
    contract, provider = env.get('MOBILE_REGISTRY_CONTRACT'), env.get('MOBILE_STORAGE_PROVIDER')
    require((contract, provider) in ((PUBLIC_CONTRACT, 's3'), (PRIVATE_CONTRACT, 'supabase-rest')),
            'unsupported or mixed storage/registry contract; held before allocation')
    if contract == PRIVATE_CONTRACT:
        require(env.get('MOBILE_SUPABASE_STORAGE_BUCKET') == PRIVATE_BUCKET
                and not env.get('MOBILE_S3_PUBLIC_BASE'), 'private delivery configuration mismatch')


def publication_mode(storage, registry, public_base):
    contract = getattr(registry, 'contract', PUBLIC_CONTRACT)
    require(contract in (PUBLIC_CONTRACT, PRIVATE_CONTRACT), 'unsupported registry contract')
    private = contract == PRIVATE_CONTRACT
    require(private == isinstance(storage, SupabaseStorage), 'mixed storage/registry contract; held')
    if private:
        require(storage.bucket == PRIVATE_BUCKET and public_base is None,
                'private delivery requires exact bucket and no public URL')
    else:
        safe_url(public_base)
    return private


def private_metadata(spec, apk):
    # Deliberately NOT consumable by legacy URL-only clients. Bootstrap requires
    # a private-capable app. Stable GitHub visibility does not change this feed.
    return dict(versionName=spec.version, versionCode=spec.code, apkSize=len(apk),
                apkSha256=hashlib.sha256(apk).hexdigest(), deliveryContract=PRIVATE_CONTRACT)


def bootstrap_requested(env):
    value = env.get('MOBILE_PUBLISH_BOOTSTRAP', '')
    require(value in ('', 'false', 'true'), 'invalid bootstrap approval')
    if value != 'true':
        return False
    require(env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and env.get('MOBILE_PUBLISH_ANDROID') == 'true'
            and env.get('MOBILE_REGISTRY_CONTRACT') == PRIVATE_CONTRACT,
            'bootstrap requires explicit manual private Android publication')
    return True


def publish(spec, apk, metadata, github, storage, registry, verify, public_base, *, bootstrap=False):
    private = publication_mode(storage, registry, public_base)
    require(type(bootstrap) is bool and (not bootstrap or private), 'bootstrap is private-contract only')
    if isinstance(github, GithubRelease) and not bootstrap:
        github.check_public_release_approval()  # Before reservation or any writes.
    if private:
        require(json_equal(metadata, private_metadata(spec, apk)), 'private bootstrap metadata mismatch; no URLs allowed')
    # Serialize cloud finalization across production CLI callers, not just CI runs.
    with registry.publication_lock() if isinstance(registry, PostgresRegistry) else nullcontext():
        return _publish(spec, apk, metadata, github, storage, registry, verify, public_base, bootstrap=bootstrap)


def _publish(spec, apk, metadata, github, storage, registry, verify, public_base, *, bootstrap=False):
    """Reserve -> GitHub exact immutable assets -> S3 conditional create/read -> advertise.

    Adapters are injected for isolated tests. SQL is authoritative for racing callers;
    failed reservations remain allocated, and a retry must use identical source/version.
    """
    private = publication_mode(storage, registry, public_base)
    if private:
        require(json_equal(metadata, private_metadata(spec, apk)), 'private bootstrap metadata mismatch; no URLs allowed')
    else:
        public_base = safe_url(public_base)
    require(bool(apk) and len(apk) <= 536870912, 'empty or oversized APK')
    verify(apk, spec)  # package/version/certificate BEFORE any external mutation
    digest = hashlib.sha256(apk).hexdigest()
    key = spec.object_key(digest)
    payload = dict(package=PACKAGE, version_name=spec.version, version_code=spec.code,
                   commit=spec.commit, tag=spec.tag, signer_sha256=spec.signer,
                   sha256=digest, size=len(apk), object_key=key)
    payload.update(storage.reference(key) if private else dict(apk_url=f'{public_base}/{key}'))
    registry.reserve(spec)
    if isinstance(github, GithubRelease):
        github.private_mode = private
        github.bootstrap_mode = bootstrap
        github.allow_published = json_equal(registry.read(spec.commit), payload)
    github.ensure(spec, apk, metadata)
    remote = github.download(spec)
    require(remote == apk, 'GitHub asset bytes differ; no promotion')
    verify(remote, spec)
    key = spec.object_key(digest)
    storage.put_if_absent(key, remote)
    require(storage.read(key) == remote, 'S3 byte readback mismatch; no advertisement')
    registry.advertise(payload)
    require(json_equal(registry.read(spec.commit), payload), 'registry readback mismatch; success not established')
    require(json_equal(registry.read_latest(), payload), 'not current registry latest; no legacy activation')
    if bootstrap:
        github.activate_bootstrap(spec)  # Explicit private handoff, never legacy latest.
    else:
        github.activate(spec)  # Approved normal releases are stable latest, private updater retained.
    return payload


def run(args):
    result = subprocess.run(args, capture_output=True, text=True, check=False, timeout=180)
    if result.returncode:
        operation = None
        if Path(args[0]).name in ('apksigner','aapt','git'):
            operation = Path(args[0]).name
        elif args[:3] in (['gh','release','create'],['gh','release','download'],['gh','release','edit']):
            operation = 'gh_release_' + args[2]
        elif args[:2] == ['gh','api']:
            operation = 'gh_api'
        if operation:
            reason = 'refused'
            for needle, label in [('Resource not accessible','permission_denied'),('HTTP 403','http_403'),('HTTP 422','http_422'),('unknown flag','unsupported_flag')]:
                if needle in result.stderr:
                    reason=label;break
            raise Held('external_' + operation + '_' + reason)
        raise Held('external verification/asset command failed')
    return result.stdout

class ApkVerifier:
    def __init__(self, apksigner, aapt): self.apksigner, self.aapt = apksigner, aapt
    def __call__(self, apk, spec):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'candidate.apk'
            path.write_bytes(apk)
            certs = run([self.apksigner, 'verify', '--verbose', '--print-certs', str(path)])
            fingerprints = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$', certs, re.M)
            schemes = re.findall(r'^(V[123](?:\.[12])? Signer): certificate SHA-256 digest: ([0-9a-fA-F]{64})$', certs, re.M)
            # Build Tools 37 labels certificate output by signature scheme.
            # Multiple schemes are allowed only for one unchanged certificate;
            # rotation, multiple signers, duplicate records and unknown output fail closed.
            if schemes:
                require(not fingerprints and re.findall(r'^Number of signers: (\d+)$',certs,re.M)==['1']
                        and len({label for label,_ in schemes})==len(schemes)
                        and all(digest.lower()==spec.signer for _,digest in schemes),
                        'signer mismatch or multiple signers')
            else:
                require([p.lower() for p in fingerprints] == [spec.signer], 'signer mismatch or multiple signers')
            require('CN=Android Debug' not in certs, 'debug signing forbidden')
            badging = run([self.aapt, 'dump', 'badging', str(path)])
            match = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
            require(match is not None and match.groups() == (PACKAGE, str(spec.code), spec.version),
                    'APK package/version mismatch')

class GithubRelease:
    """gh credentials remain in server environment; never clobber existing assets."""
    allow_published = False
    private_mode = False
    bootstrap_mode = False

    def __init__(self, *, public_bootstrap_approved=False, public_release_approved=False):
        require(type(public_bootstrap_approved) is bool, 'invalid public bootstrap approval')
        require(type(public_release_approved) is bool, 'invalid public release approval')
        self.public_bootstrap_approved = public_bootstrap_approved
        self.public_release_approved = public_release_approved
        self._release_ids = {}

    def check_public_release_approval(self):
        repo = json.loads(run(['gh', 'api', f'repos/{REPOSITORY}']))
        require(repo.get('private') is True or (repo.get('private') is False and self.public_release_approved),
                'stable release requires private repository or explicit public APK disclosure approval')

    def _release_identity(self, spec, info, release_id=None):
        require(isinstance(info, dict) and type(info.get('id')) is int and info['id'] > 0
                and info.get('tag_name') == spec.tag
                and type(info.get('draft')) is bool and type(info.get('prerelease')) is bool,
                'invalid GitHub release identity')
        require(info.get('url') == f"https://api.github.com/repos/{REPOSITORY}/releases/{info['id']}"
                and (release_id is None or info['id'] == release_id),
                'untrusted GitHub release identity')
        return info

    def _release_json(self, text):
        try:
            return json.loads(text)
        except (ValueError, TypeError):
            raise Held('invalid GitHub release response') from None

    def _release_by_id(self, spec, release_id):
        # Construct the endpoint ourselves; never follow a response-supplied URL.
        info = self._release_identity(spec, self._release_json(run(
            ['gh', 'api', f'repos/{REPOSITORY}/releases/{release_id}'])), release_id)
        self._release_ids[spec.tag] = release_id
        return info

    def _lookup_release(self, spec):
        if spec.tag in self._release_ids:
            return self._release_by_id(spec, self._release_ids[spec.tag])
        response = subprocess.run(['gh', 'api', f'repos/{REPOSITORY}/releases/tags/{spec.tag}'],
                                  capture_output=True, text=True, timeout=180)
        if not response.returncode:
            info = self._release_identity(spec, self._release_json(response.stdout))
            self._release_ids[spec.tag] = info['id']
            return info
        require(bool(re.search(r'\bHTTP 404\b', response.stderr)), 'GitHub lookup held')
        # GitHub's exact tag endpoint hides drafts. Authenticated listing is a
        # discovery read, not permission to create on errors or incomplete pages.
        # --paginate emits one JSON array per page. Decode that stream without
        # --slurp, which is unavailable on older supported gh installations.
        text = run(['gh', 'api', '--paginate', f'repos/{REPOSITORY}/releases?per_page=100'])
        pages = []
        decoder = json.JSONDecoder()
        try:
            while text.strip():
                page, end = decoder.raw_decode(text.lstrip())
                pages.append(page)
                text = text.lstrip()[end:]
        except ValueError:
            raise Held('invalid GitHub releases pages') from None
        require(isinstance(pages, list) and pages and all(isinstance(p, list) for p in pages),
                'invalid GitHub releases pages')
        matches = []
        for page in pages:
            for info in page:
                require(isinstance(info, dict) and isinstance(info.get('tag_name'), str),
                        'invalid GitHub releases entry')
                if info['tag_name'] == spec.tag:
                    matches.append(self._release_identity(spec, info))
        require(len(matches) <= 1, 'ambiguous GitHub release tag')
        if not matches:
            return None
        require(matches[0]['draft'] is True, 'non-draft hidden by GitHub tag lookup; held')
        return self._release_by_id(spec, matches[0]['id'])

    def _download(self, spec, name):
        with tempfile.TemporaryDirectory() as temp:
            run(['gh', 'release', 'download', spec.tag, '--repo', REPOSITORY,
                 '--pattern', name, '--dir', temp])
            return (Path(temp) / name).read_bytes()
    def ensure(self, spec, apk, metadata):
        # Existing tags must resolve to the exact approved source BEFORE creation.
        require(self.tag_commit(spec) in (None, spec.commit), 'existing tag source mismatch')
        # Creation requires exact-tag 404 AND successful, exhaustive draft discovery.
        info = self._lookup_release(spec)
        if info is None:
            with tempfile.TemporaryDirectory() as temp:
                path = Path(temp)
                (path / spec.apk_name).write_bytes(apk)
                (path / 'update.json').write_text(json.dumps(metadata, sort_keys=True) + '\n')
                # Explicit commit target; CLI's default branch must not choose another commit.
                run(['gh', 'release', 'create', spec.tag, '--repo', REPOSITORY,
                     '--target', spec.commit, '--draft', '--latest=false', '--title', f'Fireside Group {spec.tag}',
                     '--notes', f'Android {spec.version} ({spec.code})',
                     str(path / spec.apk_name), str(path / 'update.json')])
            info = self._lookup_release(spec)
        if info is None:
            raise Held('created GitHub draft not found; held')
        require((info['draft'] or (self.allow_published and info['prerelease'] == self.bootstrap_mode))
                and (not info['draft'] or not info['prerelease']),
                'unverified public release must not precede registry receipt')
        # Resolve peeled tag to source rather than trusting mutable target_commitish.
        tag_commit = self.tag_commit(spec)
        require(tag_commit == spec.commit or (info['draft'] and tag_commit is None
                and info.get('target_commitish') == spec.commit), 'release tag source mismatch')
        require(self._download(spec, spec.apk_name) == apk, 'existing GitHub APK conflict')
        require(json_equal(json.loads(self._download(spec, 'update.json')), metadata), 'existing metadata conflict')
    def tag_commit(self, spec):
        result = subprocess.run(['gh', 'api', f'repos/{REPOSITORY}/git/ref/tags/{spec.tag}'],
                                capture_output=True, text=True, timeout=180)
        if result.returncode:
            require('HTTP 404' in result.stderr, 'GitHub tag lookup held')
            return None
        obj = json.loads(result.stdout)['object']
        for _ in range(5):
            if obj['type'] == 'commit':
                return obj['sha']
            require(obj['type'] == 'tag' and re.fullmatch('[0-9a-f]{40}', obj['sha']), 'invalid tag object')
            obj = json.loads(run(['gh', 'api', f"repos/{REPOSITORY}/git/tags/{obj['sha']}"]))['object']
        raise Held('tag nesting limit exceeded')
    def download(self, spec): return self._download(spec, spec.apk_name)
    def activate_bootstrap(self, spec):
        # Do not turn private delivery approval into public APK disclosure.
        repo = json.loads(run(['gh', 'api', f'repos/{REPOSITORY}']))
        require(repo.get('private') is True or (repo.get('private') is False and self.public_bootstrap_approved),
                'bootstrap requires private repository or explicit public APK disclosure approval')
        info = self._lookup_release(spec)
        if info is None:
            raise Held('bootstrap release absent')
        tag_commit = self.tag_commit(spec)
        require(tag_commit == spec.commit or (info.get('draft') is True and tag_commit is None
                and info.get('target_commitish') == spec.commit), 'bootstrap source mismatch')
        run(['gh', 'release', 'edit', spec.tag, '--repo', REPOSITORY,
             '--draft=false', '--prerelease=true', '--latest=false',
             '--notes', 'Manual private-capable Android bootstrap. Download the APK asset (GitHub access required for private repositories). '
             'update.json is a receipt, NOT a legacy updater feed. Confirm installation on Android.'])
        info = self._release_by_id(spec, info['id'])
        require(self.tag_commit(spec) == spec.commit, 'bootstrap source readback mismatch')
        require(info.get('tag_name') == spec.tag and info.get('draft') is False
                and info.get('prerelease') is True, 'bootstrap publication readback mismatch')

    def activate(self, spec):
        self.check_public_release_approval()
        info = self._lookup_release(spec)
        if info is None:
            raise Held('activation release absent')
        tag_commit = self.tag_commit(spec)
        require(tag_commit == spec.commit or (info.get('draft') is True and tag_commit is None
                and info.get('target_commitish') == spec.commit), 'activation source mismatch')
        run(['gh', 'release', 'edit', spec.tag, '--repo', REPOSITORY,
             '--draft=false', '--prerelease=false', '--latest=true',
             '--notes', f'Android {spec.version} ({spec.code}). Install over the existing app without uninstalling. '
             'update.json is an integrity receipt, not a legacy URL-only updater feed.'])
        exact = self._release_by_id(spec, info['id'])
        require(exact['draft'] is False and exact['prerelease'] is False,
                'stable publication exact release readback mismatch')
        info = json.loads(run(['gh', 'api', f'repos/{REPOSITORY}/releases/latest']))
        require(self.tag_commit(spec) == spec.commit, 'published source readback mismatch')
        require(info.get('tag_name') == spec.tag and not info.get('draft', True)
                and not info.get('prerelease', True), 'legacy latest readback mismatch')

class S3Storage:
    def __init__(self, client, bucket): self.client, self.bucket = client, bucket
    def put_if_absent(self, key, data):
        from botocore.exceptions import ClientError
        try:
            self.client.put_object(Bucket=self.bucket, Key=key, Body=data,
                IfNoneMatch='*', ContentType='application/vnd.android.package-archive',
                ChecksumSHA256=__import__('base64').b64encode(hashlib.sha256(data).digest()).decode())
        except ClientError as exc:
            require(exc.response.get('ResponseMetadata', {}).get('HTTPStatusCode') == 412,
                    'S3 conditional create failed; no overwrite fallback')
        # Even 412 must be followed by exact byte readback by orchestrator.
    def read(self, key):
        body = self.client.get_object(Bucket=self.bucket, Key=key)['Body']
        try: return body.read()
        finally: body.close()

class _NoStorageRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward publisher credentials or replay a write on redirects.
        return None


class SupabaseStorage:
    """Private native REST objects, NOT a staff download or registry API.

    Only create/select are used. Deployment must separately enforce scoped
    insert/select-only authority; this adapter cannot prove remote RLS grants.
    No retries: a broken POST response may mean the create already committed.
    """
    def __init__(self, endpoint, bucket, token, *, allow_loopback_http=False):
        parsed = urlsplit(endpoint)
        if allow_loopback_http and parsed.scheme == 'http' and parsed.hostname == '127.0.0.1':
            require(not parsed.username and not parsed.password and not parsed.query
                    and not parsed.fragment, 'invalid loopback storage URL')
            endpoint = endpoint.rstrip('/')
        else:
            endpoint = safe_url(endpoint)
        require(urlsplit(endpoint).path == '/storage/v1', 'native Storage endpoint must end /storage/v1')
        require(bool(re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,99}', bucket)), 'invalid Storage bucket')
        require(bool(token) and all(33 <= ord(c) <= 126 for c in token),
                'explicit server-only Storage token required')
        self.endpoint, self.bucket, self._token = endpoint, bucket, token
        # Ignore ambient proxies and disallow redirects. TLS verification is default.
        self._opener = build_opener(ProxyHandler({}), _NoStorageRedirect())

    def reference(self, key):
        require(isinstance(key, str) and len(key) <= 1024
                and all(re.fullmatch(r'[A-Za-z0-9_-][A-Za-z0-9_.-]*', p)
                        for p in key.split('/')), 'invalid Storage object key')
        return dict(provider='supabase-rest', bucket=self.bucket, object_key=key)

    def _request(self, method, key, data=None):
        self.reference(key)
        url = f'{self.endpoint}/object/{self.bucket}/{quote(key, safe="/")}'
        headers = {'Authorization': 'Bearer ' + self._token, 'apikey': self._token}
        if method == 'POST':
            if not isinstance(data, bytes):
                raise Held('Storage upload requires exact APK bytes')
            headers.update({'x-upsert': 'false', 'Content-Type': 'application/vnd.android.package-archive'})
            if len(data) > 1024 * 1024:
                return self._large_post(url, headers, data)
        if method == 'GET':
            return self._ranged_get(url, headers)
        req = Request(url, data=data, headers=headers, method=method)
        try:
            with self._opener.open(req, timeout=30) as response:
                return response.status, response.read()
        except HTTPError as exc:
            try:
                # Error bodies are bounded and never included in Held diagnostics.
                return exc.code, exc.read(4097)
            finally:
                exc.close()
        except Exception:
            raise Held('Storage network outcome uncertain; no automatic retry or advertisement') from None

    def _ranged_get(self, url, headers):
        # Bound each ingress response, not just the complete artifact. A truncated
        # response is never appended; ranges must cover one strong-ETag snapshot.
        chunk, limit = 4 * 1024 * 1024, 536870912
        parts, start, total, etag = [], 0, None, None
        while total is None or start < total:
            end = min(start + chunk, total or chunk) - 1
            request_headers = dict(headers, Range=f'bytes={start}-{end}')
            if etag is not None:
                request_headers['If-Match'] = etag
            status, body, response = self._curl_request(
                url, request_headers, None, method='GET', max_size=chunk)
            if start == 0 and status != 206:
                if status == 200:
                    require(response.get('content-length') == str(len(body)),
                            'Storage complete read length mismatch')
                return status, body
            require(status == 206, 'Storage range unsupported or snapshot changed; no advertisement')
            match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', response.get('content-range', ''))
            if match is None:
                raise Held('Storage invalid Content-Range')
            first, last, size = map(int, match.groups())
            require(0 < size <= limit and first == start
                    and last == min(start + chunk, size) - 1
                    and len(body) == last - first + 1
                    and response.get('content-length') == str(len(body)),
                    'Storage range size or offset mismatch')
            current_etag = response.get('etag', '')
            require(re.fullmatch(r'"[\x21\x23-\x7e]+"', current_etag) is not None,
                    'Storage strong ETag required for ranged read')
            if total is None:
                total, etag = size, current_etag
            require(size == total and current_etag == etag, 'Storage ranged snapshot changed')
            parts.append(body)
            start = last + 1
        return 200, b''.join(parts)

    def _large_post(self, url, headers, data):
        status, body, _ = self._curl_request(url, headers, data)
        return status, body

    def _curl_request(self, url, headers, data, *, method='POST', max_size=536870912):
        # Live large-APK urllib/OpenSSL transfers fail on this ingress; curl's bounded
        # HTTP/1.1 transfer is used for large POSTs and byte-readback. Credentials stay on stdin,
        # never in argv/files/logs; no curlrc, proxy, redirects or automatic retry.
        try:
            with tempfile.NamedTemporaryFile(prefix='mobile-apk-transport-') as body, \
                    tempfile.NamedTemporaryFile(prefix='mobile-apk-readback-') as downloaded, \
                    tempfile.NamedTemporaryFile(prefix='mobile-apk-headers-') as header_file:
                config = ['url = ' + json.dumps(url), 'request = ' + json.dumps(method)]
                if data is not None:
                    body.write(data)
                    body.flush()
                    config.append('data-binary = ' + json.dumps('@' + body.name))
                config += ['header = ' + json.dumps(k + ': ' + v) for k, v in headers.items()]
                result = subprocess.run(
                    ['curl', '-q', '--config', '-', '--http1.1', '--silent', '--show-error',
                     '--noproxy', '*', '--proto', '=http,https', '--max-redirs', '0',
                     '--connect-timeout', '10', '--max-time', '180', '--retry', '0',
                     '--max-filesize', str(max_size), '--dump-header', header_file.name,
                     '--output', downloaded.name, '--write-out', '%{http_code}'],
                    input='\n'.join(config).encode(), capture_output=True, timeout=190)
                require(result.returncode == 0, 'Storage network outcome uncertain; no automatic retry or advertisement')
                code = result.stdout.strip()
                require(re.fullmatch(b'[0-9]{3}', code), 'Storage response outcome uncertain')
                require(Path(downloaded.name).stat().st_size <= max_size, 'Storage readback size exceeds limit')
                downloaded.seek(0)
                require(Path(header_file.name).stat().st_size <= 65536, 'Storage headers exceed limit')
                # curl may record interim 100 responses. Only final headers apply.
                blocks = Path(header_file.name).read_bytes().strip().split(b'\r\n\r\n')
                lines = blocks[-1].decode('iso-8859-1').split('\r\n')
                require(lines[0].startswith('HTTP/1.1 ' + code.decode()), 'Storage final status mismatch')
                parsed = {}
                for line in lines[1:]:
                    name, sep, value = line.partition(':')
                    require(sep and name.lower() not in parsed, 'Storage invalid or duplicate headers')
                    parsed[name.lower()] = value.strip()
                require(parsed.get('content-encoding', 'identity') == 'identity', 'Storage encoded range refused')
                return int(code), downloaded.read(), parsed
        except Held:
            raise
        except Exception:
            raise Held('Storage network outcome uncertain; no automatic retry or advertisement') from None

    def put_if_absent(self, key, data):
        status, body = self._request('POST', key, data)
        if status not in (200, 201):
            duplicate = False
            if status in (400, 409) and len(body) <= 4096:
                try:
                    error = json.loads(body)
                    duplicate = (isinstance(error, dict)
                                 and error.get('statusCode') in ('409', 409)
                                 and error.get('error') == 'Duplicate')
                except (ValueError, UnicodeError):
                    pass
            require(duplicate, 'Storage create held; no overwrite fallback or automatic retry')
        # Duplicate is never success by itself; verify exact bytes even for direct callers.
        require(self.read(key) == data, 'Storage byte readback mismatch; no advertisement')

    def read(self, key):
        status, data = self._request('GET', key)
        require(status == 200, 'Storage authenticated read held; no advertisement')
        return data


def storage_from_environment(env):
    """Explicit provider selection; never infer Supabase from S3 credentials/hostname."""
    require(env.get('MOBILE_STORAGE_APPROVED') == 'true', 'storage owner approval absent')
    provider = env.get('MOBILE_STORAGE_PROVIDER')
    require(provider in ('s3', 'supabase-rest'), 'explicit approved storage provider required')
    if provider == 'supabase-rest':
        return SupabaseStorage(env.get('MOBILE_SUPABASE_STORAGE_ENDPOINT', ''),
                               env.get('MOBILE_SUPABASE_STORAGE_BUCKET', ''),
                               env.get('MOBILE_SUPABASE_STORAGE_TOKEN', '')), None
    endpoint = safe_url(env.get('MOBILE_S3_ENDPOINT', ''))
    # Supabase S3 has been observed ignoring conditional creates. Never use that
    # API via this generic adapter (including a custom Supabase hostname).
    require(not urlsplit(endpoint).path.rstrip('/').endswith('/storage/v1/s3'),
            'Supabase S3 conditional create unsupported; select native REST')
    public_base = safe_url(env.get('MOBILE_S3_PUBLIC_BASE', ''))
    bucket, region = env.get('MOBILE_S3_BUCKET', ''), env.get('MOBILE_S3_REGION', '')
    require(bucket and region, 'approved bucket/region missing')
    access, secret = env.get('AWS_ACCESS_KEY_ID', ''), env.get('AWS_SECRET_ACCESS_KEY', '')
    require(access and secret, 'explicit server-only S3 credentials missing; no discovery fallback')
    import boto3
    client = boto3.client('s3', endpoint_url=endpoint, region_name=region,
                          aws_access_key_id=access, aws_secret_access_key=secret,
                          aws_session_token=env.get('AWS_SESSION_TOKEN') or None)
    return S3Storage(client, bucket), public_base


class PostgresRegistry:
    def __init__(self, dsn, *, contract=PUBLIC_CONTRACT, schema='mobile_release'):
        require(bool(re.fullmatch(r'[a-z_][a-z0-9_]{0,62}', schema)), 'invalid registry schema')
        self.dsn, self.contract, self.schema = dsn, contract, schema
    @classmethod
    def from_environment(cls, env):
        require(env.get('MOBILE_REGISTRY_CONTRACT') in (PUBLIC_CONTRACT, PRIVATE_CONTRACT)
                and env.get('MOBILE_REGISTRY_DSN'), 'scoped registry contract/DSN unconfigured; held')
        from psycopg.conninfo import conninfo_to_dict
        info = conninfo_to_dict(env['MOBILE_REGISTRY_DSN'])
        require(info.get('sslmode') == 'verify-full' and info.get('sslrootcert')
                and info.get('host') and not info['host'].startswith('/'),
                'production registry requires verified TLS hostname and CA; local tests use explicit adapter')
        return cls(env['MOBILE_REGISTRY_DSN'], contract=env['MOBILE_REGISTRY_CONTRACT'])
    def call(self, sql, args):
        import psycopg
        with psycopg.connect(self.dsn, connect_timeout=10, options='-c statement_timeout=30000') as conn:
            return conn.execute(sql.replace('mobile_release.', self.schema + '.'), args).fetchone()[0]
    @contextmanager
    def publication_lock(self):
        import psycopg
        with psycopg.connect(self.dsn, connect_timeout=10, autocommit=True,
                            options='-c statement_timeout=30000') as conn:
            conn.execute('select pg_advisory_lock(721434875)')
            try:
                yield
            finally:
                conn.execute('select pg_advisory_unlock(721434875)')

    def allocate(self, commit, version, signer):
        return self.call('select mobile_release.allocate(%s,%s,%s)', (commit, version, signer))
    def reserve(self, spec):
        return self.call('select mobile_release.reserve(%s,%s,%s,%s)',
                         (spec.commit, spec.version, spec.code, spec.signer))
    def advertise(self, payload):
        return self.call('select mobile_release.advertise(%s::jsonb)', (json.dumps(payload),))
    def read_latest(self):
        return self.call('select mobile_release.latest()', ())
    def read(self, commit):
        return self.call('select mobile_release.receipt(%s)', (commit,))


def prepare_registry_ca(env):
    """Materialize approved nonsecret PEM at the issuer's exact runner DSN path."""
    from psycopg.conninfo import conninfo_to_dict
    runner = Path(env.get('RUNNER_TEMP', ''))
    require(runner.is_absolute() and runner.is_dir(), 'runner CA directory required')
    path = runner / 'mobile-registry-ca.pem'
    try:
        info = conninfo_to_dict(env.get('MOBILE_REGISTRY_DSN', ''))
    except Exception:
        raise Held('invalid scoped registry DSN') from None
    require(info.get('sslmode') == 'verify-full' and info.get('sslrootcert') == str(path),
            'registry DSN must use verify-full and exact runner CA path')
    pem = env.get('MOBILE_REGISTRY_CA_PEM', '')
    require(0 < len(pem) <= 65536 and re.fullmatch(
        r'(?:-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\s*)+', pem),
        'approved CA requires literal certificate-only PEM, not base64 or escaped newlines')
    try:
        ssl.create_default_context(cadata=pem)
    except (ssl.SSLError, ValueError):
        raise Held('approved registry CA certificate invalid') from None
    # Exclusive creation refuses stale files/symlinks; hosted jobs have fresh temp dirs.
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as out:
        out.write(pem)


def admit(env):
    # actor is the ORIGINAL run initiator (and privileges); triggering_actor is
    # the person rerunning it. Neither an owner rerun of a stranger's push nor a
    # stranger rerun of an owner's push grants publication authority.
    require(env.get('GITHUB_ACTOR') == 'josephndex'
            and env.get('GITHUB_TRIGGERING_ACTOR') == 'josephndex',
            'publication requires approved original and triggering owner actor')
    require(env.get('GITHUB_REF') == 'refs/heads/main'
            and env.get('MOBILE_RELEASE_APPROVED') == 'true'
            and (env.get('GITHUB_EVENT_NAME') == 'push'
                 or (env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
                     and env.get('MOBILE_PUBLISH_ANDROID') == 'true')),
            'approved main push or explicit manual publication required')

def check_protection(info, branches):
    policy = info.get('deployment_branch_policy') or {}
    reviewers = [rule for rule in info.get('protection_rules', [])
                 if rule.get('type') == 'required_reviewers']
    require(info.get('can_admins_bypass') is False
            and policy.get('custom_branch_policies') is True
            and policy.get('protected_branches') is False
            and not reviewers
            and branches.get('total_count') == 1
            and branches.get('branch_policies') == [dict(name='main', type='branch')],
            'automatic protected environment requires no reviewers/no bypass/main-only admission')

def verify_environment():
    base = f'repos/{REPOSITORY}/environments/mobile-release'
    info = json.loads(run(['gh', 'api', base]))
    branches = json.loads(run(['gh', 'api', base + '/deployment-branch-policies']))
    # IDs and URLs are not admission semantics; reject incomplete pagination.
    branches['branch_policies'] = [dict(name=p.get('name'), type=p.get('type'))
                                    for p in branches.get('branch_policies', [])]
    check_protection(info, branches)

def reuse_original(spec, destination):
    result = subprocess.run(['gh', 'api', f'repos/{REPOSITORY}/releases/tags/{spec.tag}'],
                            capture_output=True, text=True, timeout=180)
    if result.returncode:
        require('HTTP 404' in result.stderr, 'retry asset lookup held')
        return False
    info = json.loads(result.stdout)
    require(info.get('target_commitish') == spec.commit or GithubRelease().tag_commit(spec) == spec.commit,
            'retry source conflict')
    destination.mkdir(exist_ok=True)
    for name in (spec.apk_name, 'update.json'):
        (destination / name).write_bytes(GithubRelease()._download(spec, name))
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk')
    parser.add_argument('--metadata')
    parser.add_argument('--apksigner')
    parser.add_argument('--aapt')
    parser.add_argument('--allocate', action='store_true')
    parser.add_argument('--reuse', action='store_true')
    parser.add_argument('--prepare-registry-ca', action='store_true')
    args = parser.parse_args()
    if args.prepare_registry_ca:
        admit(os.environ)
        verify_environment()
        prepare_registry_ca(os.environ)
        return
    if args.reuse:
        require(os.environ.get('GITHUB_REF') == 'refs/heads/main', 'retry main-only')
        spec = Spec(os.environ['MOBILE_BUILD_NAME'], int(os.environ['MOBILE_BUILD_CODE']),
                    os.environ['GITHUB_SHA'], '0'*64)
        reused = reuse_original(spec, Path('release'))
        with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
            out.write('reused=' + str(reused).lower() + '\n')
        return
    # Independent runtime admission complements Actions guards. No PR or tag-trigger publish.
    admit(os.environ)
    verify_environment()
    commit = run(['git', 'rev-parse', 'HEAD']).strip()
    require(commit == os.environ.get('GITHUB_SHA'), 'checkout/source mismatch')
    run(['git', 'fetch', 'origin', 'main', '--no-tags'])
    require(run(['git', 'rev-parse', 'origin/main']).strip() == commit, 'main advanced; replan release')
    check_contract_environment(os.environ)
    bootstrap = bootstrap_requested(os.environ)
    registry = PostgresRegistry.from_environment(os.environ)
    if args.allocate:
        pubspec = Path('pubspec.yaml')
        text = pubspec.read_text()
        version = re.search(r'^version:\s*([^+\s]+)', text, re.M)[1]
        plan = registry.allocate(commit, version, os.environ.get('MOBILE_PRODUCTION_SIGNER_SHA256', ''))
        Spec(plan['version_name'], plan['code'], commit,
             os.environ.get('MOBILE_PRODUCTION_SIGNER_SHA256', ''))
        pubspec.write_text(re.sub(r'^version:.*$', f"version: {plan['version_name']}+{plan['code']}", text, flags=re.M))
        with open(os.environ['GITHUB_ENV'], 'a') as out:
            out.write(f"MOBILE_BUILD_CODE={plan['code']}\nMOBILE_BUILD_NAME={plan['version_name']}\n")
        return
    require(all([args.apk, args.metadata, args.apksigner, args.aapt]), 'APK verification inputs missing')
    metadata = json.loads(Path(args.metadata).read_text())
    spec = Spec(metadata['versionName'], metadata['versionCode'], commit,
                os.environ.get('MOBILE_PRODUCTION_SIGNER_SHA256', ''))
    apk = Path(args.apk).read_bytes()
    expected = f'https://github.com/{REPOSITORY}/releases/download/{spec.tag}/{spec.apk_name}'
    require((json_equal(metadata, private_metadata(spec, apk)) if registry.contract == PRIVATE_CONTRACT
             else metadata.get('apkUrl') == expected) and type(metadata.get('apkSize')) is int
            and metadata.get('apkSize') == len(apk)
            and metadata.get('apkSha256') == hashlib.sha256(apk).hexdigest(), 'legacy metadata mismatch')
    registry = PostgresRegistry.from_environment(os.environ)
    storage, public_base = storage_from_environment(os.environ)
    public_bootstrap = os.environ.get('MOBILE_BOOTSTRAP_PUBLIC_APPROVED', '')
    require(public_bootstrap in ('', 'false', 'true') and (public_bootstrap != 'true' or bootstrap),
            'public disclosure approval requires explicit bootstrap dispatch')
    public_release = os.environ.get('MOBILE_PUBLIC_RELEASE_APPROVED', '')
    require(public_release in ('', 'false', 'true'), 'invalid public release approval')
    payload = publish(spec, apk, metadata, GithubRelease(public_bootstrap_approved=public_bootstrap == 'true',
                      public_release_approved=public_release == 'true'), storage, registry,
                      ApkVerifier(args.apksigner, args.aapt), public_base, bootstrap=bootstrap)
    print(json.dumps({'status': ('private-bootstrap-published' if bootstrap else 'private-registry-and-stable-latest-verified') if registry.contract == PRIVATE_CONTRACT
                     else 'verified', 'versionCode': spec.code, 'sha256': payload['sha256']}))

if __name__ == '__main__':
    try:
        main()
    except Held as exc:
        print(f'Release HELD: {exc}', file=__import__('sys').stderr)
        raise SystemExit(1)
    except Exception:
        # SDK/SQL errors can contain credentials or server response bodies.
        print('Release HELD: publication incomplete; investigate with protected diagnostics.', file=__import__('sys').stderr)
        raise SystemExit(1)
