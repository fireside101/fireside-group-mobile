"""Exact retained-bootstrap promotion only. No build, allocation or generic rollback."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import mobile_release as r

SOURCE='cd65ca3be70fbab17e9b492fa1aa9a47c4742418'
SHA='d177f653c3dbc60057577336c6dd47c0babcea2e88344d79e4b57e4b0f4f0de6'
SIGNER='701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9'
ALLOWED={'.github/workflows/mobile-bootstrap-recovery.yml','tool/recover_bootstrap.py','tool/tests/test_bootstrap_recovery.py'}


def source_guard():
    head=r.run(['git','rev-parse','HEAD']).strip()
    r.require(head==os.environ.get('GITHUB_SHA'),'recovery checkout mismatch')
    r.require(r.run(['git','rev-parse','origin/main']).strip()==head,'recovery main advanced')
    changes=set(r.run(['git','diff','--name-only',SOURCE,head]).splitlines())
    r.require(changes<=ALLOWED,'recovery app/publisher source changed')


def diagnostic_run(args):
    result=subprocess.run(args,capture_output=True,text=True,timeout=180)
    if result.returncode:
        executable=Path(args[0]).name
        operation='external'
        if executable in ('apksigner','aapt','git'):
            operation=executable
        elif executable=='gh' and args[1:3] in (['release','create'],['release','download'],['release','edit']):
            operation='gh_release_'+args[2]
        elif executable=='gh' and args[1:2]==['api']:
            operation='gh_api'
        reason='refused'
        for needle,label in [('Resource not accessible','permission_denied'),('HTTP 403','http_403'),('HTTP 422','http_422'),('unknown flag','unsupported_flag'),('no artifacts','artifact_absent')]:
            if needle in result.stderr:
                reason=label;break
        raise r.Held('recovery_'+operation+'_'+reason)
    return result.stdout


def main():
    r.run=diagnostic_run
    r.admit(os.environ)
    r.require(r.bootstrap_requested(os.environ),'explicit bootstrap approval required')
    r.require(os.environ.get('MOBILE_BOOTSTRAP_PUBLIC_APPROVED')=='true','explicit public approval required')
    r.verify_environment()
    source_guard()
    r.check_contract_environment(os.environ)
    r.prepare_registry_ca(os.environ)
    spec=r.Spec('1.0.7',7,SOURCE,SIGNER)
    apk=(Path('release')/spec.apk_name).read_bytes()
    r.require(len(apk)==59814319 and hashlib.sha256(apk).hexdigest()==SHA,'retained APK conflict')
    metadata=json.loads(Path('release/update.json').read_text())
    r.require(r.json_equal(metadata,r.private_metadata(spec,apk)),'retained metadata conflict')
    registry=r.PostgresRegistry.from_environment(os.environ)
    storage, public_base=r.storage_from_environment(os.environ)
    r.require(public_base is None,'private-only recovery')
    result=r.publish(spec,apk,metadata,r.GithubRelease(public_bootstrap_approved=True),storage,registry,
                     r.ApkVerifier(sys.argv[1]+'/apksigner',sys.argv[1]+'/aapt'),None,bootstrap=True)
    print(json.dumps({'state':'published','source':SOURCE,'sha256':result['sha256'],'code':7}))


if __name__=='__main__':
    try:
        main()
    except Exception as exc:
        # Core Holds are curated diagnostics; never expose subprocess stderr or credentials.
        reason=str(exc) if isinstance(exc,r.Held) else 'recovery_held'
        print('Recovery HELD: '+reason,file=sys.stderr)
        sys.exit(1)
