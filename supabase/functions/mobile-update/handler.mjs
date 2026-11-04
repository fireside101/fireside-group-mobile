// LOCAL CANDIDATE: shared executable route used by the Edge entrypoint and Node tests.
// No SDK dependency, no caller-selected host, subject, bucket or object key.
export const ORIGIN = 'https://supabase.firesideafrica.cloud';
export const ARTIFACT_KEYS = ['package','version_code','version_name','commit','tag','signer_sha256','sha256','size','provider','bucket','object_key'];
export function validateArtifact(a) {
  if (!a || typeof a !== 'object' || Array.isArray(a) ||
      Object.keys(a).sort().join() !== [...ARTIFACT_KEYS].sort().join() ||
      a.package !== 'com.firesideafrica.firesidegroup' ||
      a.provider !== 'supabase-rest' || a.bucket !== 'fireside-mobile-releases' ||
      !Number.isSafeInteger(a.version_code) || a.version_code < 1 || a.version_code > 2100000000 ||
      !Number.isSafeInteger(a.size) || a.size < 1 || a.size > 536870912 ||
      !/^[a-f0-9]{64}$/.test(a.sha256) || !/^[a-f0-9]{64}$/.test(a.signer_sha256) ||
      !/^[a-f0-9]{40}$/.test(a.commit) || !/^\d+\.\d+\.\d+$/.test(a.version_name) ||
      a.tag !== `v${a.version_name}` ||
      a.object_key !== `${a.package}/${a.version_code}/${a.commit}/${a.sha256}.apk`) throw Error('invalid artifact');
  return a;
}
const stable = a => JSON.stringify(ARTIFACT_KEYS.map(k => a[k]));
class Denied extends Error { constructor(status) { super('denied'); this.status=status; } }
const reply = (status,body) => Response.json(body,{status,headers:{'Cache-Control':'no-store','Pragma':'no-cache','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'}});

export function createHandler({url,serverKey,fetch=globalThis.fetch,now=()=>Date.now()}) {
  // Explicit production origin; never infer it from request Host or a phone payload.
  if (url !== ORIGIN || !serverKey) throw Error('private delivery not configured');
  const call = async (path,init) => fetch(`${url}${path}`,{...init,redirect:'error',signal:AbortSignal.timeout(8000)});
  const auth = async (authorization) => {
    const response = await call('/auth/v1/user',{headers:{Authorization:authorization,apikey:serverKey}});
    if (!response.ok) throw new Denied(401);
    const u=await response.json();
    if (!/^[a-f0-9-]{36}$/.test(u.id??'') || !u.email || !u.email_confirmed_at || u.is_anonymous !== false) throw new Denied(403);
    return u.id;
  };
  const authorize = async subject => {
    const response=await call('/rest/v1/rpc/mobile_update_authorize',{method:'POST',headers:{Authorization:`Bearer ${serverKey}`,apikey:serverKey,'Content-Type':'application/json'},body:JSON.stringify({subject})});
    if (response.status===401 || response.status===403) throw new Denied(403);
    if (!response.ok) throw Error('authorization unavailable');
    const artifact=await response.json();
    return artifact===null ? null : validateArtifact(artifact);
  };
  return async request => {
    try {
      if (request.method !== 'POST') return reply(405,{error:'method_not_allowed'});
      const authorization=request.headers.get('authorization')??'';
      if (!/^Bearer [A-Za-z0-9_.-]{1,8192}$/.test(authorization)) return reply(401,{error:'unauthorized'});
      // No identity/locator/version selected by caller. Bound input before parsing.
      if (Number(request.headers.get('content-length')??0)>64) return reply(400,{error:'invalid_request'});
      const reader=request.body?.getReader();
      let text='';
      if(reader) {
        const decoder=new TextDecoder();
        let bytes=0;
        while(true) {
          const {value,done}=await reader.read();
          if(done) break;
          bytes+=value.byteLength;
          if(bytes>64) { await reader.cancel(); return reply(400,{error:'invalid_request'}); }
          text+=decoder.decode(value,{stream:true});
        }
        text+=decoder.decode();
      }
      let body;
      try { body=JSON.parse(text); } catch { return reply(400,{error:'invalid_request'}); }
      if (!body || Array.isArray(body) || typeof body!=='object' || Object.keys(body).length) return reply(400,{error:'invalid_request'});
      const subject=await auth(authorization);
      const artifact=await authorize(subject);
      if (artifact===null) return reply(200,{release:null});
      const issuedAt=now();
      const signed=await call(`/storage/v1/object/sign/${artifact.bucket}/${artifact.object_key}`,{method:'POST',headers:{Authorization:`Bearer ${serverKey}`,apikey:serverKey,'Content-Type':'application/json'},body:JSON.stringify({expiresIn:60})});
      if(!signed.ok) throw Error('signing unavailable');
      const data=await signed.json();
      if(typeof data.signedURL !== 'string') throw Error('invalid signed url');
      const raw=data.signedURL;
      const download=new URL(raw.startsWith('/object/')?`/storage/v1${raw}`:raw,url);
      if (download.origin!==url || download.username || download.password || download.hash ||
          download.pathname!==`/storage/v1/object/sign/${artifact.bucket}/${artifact.object_key}` ||
          download.href.includes('%') || [...download.searchParams.keys()].join()!=='token' ||
          !/^[A-Za-z0-9_.-]{1,4096}$/.test(download.searchParams.get('token')??'')) throw Error('untrusted signed url');
      // Recheck after signing, so pause/revocation/identity change in-flight is not returned.
      if(await auth(authorization)!==subject) throw new Denied(403);
      const fresh=await authorize(subject);
      if(!fresh || stable(fresh)!==stable(artifact)) return reply(409,{error:'authorization_changed'});
      if(now()>=issuedAt+60000) throw Error('expired signing');
      return reply(200,{release:{...artifact,download_url:download.href,expires_at:new Date(issuedAt+60000).toISOString()}});
    } catch(error) {
      const status=error instanceof Denied?error.status:503;
      // Never reflect tokens, PI fields, provider errors, URLs or stack traces.
      return reply(status,{error:status===503?'update_unavailable':'unauthorized'});
    }
  };
}
