import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../../functions/mobile-update/handler.mjs';

const origin='https://supabase.firesideafrica.cloud';
const identity={id:'11111111-1111-4111-8111-111111111111', email:'employee@example.test',email_confirmed_at:'2026-01-01T00:00:00Z',is_anonymous:false};
const artifact={package:'com.firesideafrica.firesidegroup',version_code:7,version_name:'1.0.7',tag:'v1.0.7',commit:'b'.repeat(40),signer_sha256:'a'.repeat(64),sha256:'c'.repeat(64),size:3,provider:'supabase-rest',bucket:'fireside-mobile-releases'};
artifact.object_key=`${artifact.package}/7/${artifact.commit}/${artifact.sha256}.apk`;
function fixture(options={}) {
  const calls=[];
  let checks=0;
  const fetch=async(url, init)=>{
    calls.push({url,init});
    assert.equal(init.redirect,'error');
    if(options.offline) throw Error('server secret must not escape');
    if(url.endsWith('/auth/v1/user')) return Response.json(options.user??identity,{status:options.authStatus??200});
    if(url.endsWith('/rest/v1/rpc/mobile_update_authorize')) {
      assert.deepEqual(JSON.parse(init.body),{subject:identity.id});
      checks++;
      if(options.denied) return Response.json({message:'private PI details'},{status:403});
      if(options.changeAfterSign && checks>1) return Response.json({...artifact,signer_sha256:'d'.repeat(64)});
      return Response.json(options.paused || (options.revokeAfterSign && checks>1) ? null : {...artifact,...options.artifact});
    }
    assert.equal(url,`${origin}/storage/v1/object/sign/${artifact.bucket}/${artifact.object_key}`);
    assert.deepEqual(JSON.parse(init.body),{expiresIn:60});
    return Response.json({signedURL:options.signedURL??`/object/sign/${artifact.bucket}/${artifact.object_key}?token=ephemeral`});
  };
  const handler=createHandler({url:origin,serverKey:'synthetic-server-only',fetch});
  return {calls,handler};
}
const req=(headers={Authorization:'Bearer employee-session'})=>new Request(`${origin}/functions/v1/mobile-update`,{method:'POST',headers,body:'{}'});
test('authenticated route delivers only allowlisted stable metadata and short URL',async()=>{
  const {handler,calls}=fixture();
  const response=await handler(req());
  assert.equal(response.status,200);
  assert.equal(response.headers.get('cache-control'),'no-store');
  const text=await response.text();
  const body=JSON.parse(text);
  assert.equal(body.release.object_key,artifact.object_key);
  assert.equal(new URL(body.release.download_url).searchParams.get('token'),'ephemeral');
  for(const value of ['synthetic-server-only','employee-session','employee@example.test',identity.id]) assert.ok(!text.includes(value));
  assert.equal(calls.filter(c=>c.url.endsWith('/auth/v1/user')).length,2);
});
for(const [label,options,status] of [
  ['unauthenticated',{},401],['invalid token',{authStatus:401},401],
  ['anonymous',{user:{...identity,is_anonymous:true}},403],
  ['unconfirmed',{user:{...identity,email_confirmed_at:null}},403],
  ['inactive/deleted/ambiguous SQL authorization refusal',{denied:true},403],
  ['paused/revoked',{paused:true},200],['revoked while signing',{revokeAfterSign:true},409],
  ['artifact changes while signing',{changeAfterSign:true},409],
  ['offline',{offline:true},503],['changed object identity',{artifact:{object_key:'../private'}},503],
  ['credential-bearing artifact',{artifact:{apk_url:'https://private/?secret=x'}},503],
  ['foreign signed URL',{signedURL:'https://evil.example/path?token=x'},503],
  ['public path',{signedURL:`/object/public/${artifact.bucket}/${artifact.object_key}?token=x`},503],
]) test(label,async()=>{
  const {handler,calls}=fixture(options);
  const response=await handler(req(label==='unauthenticated'?{}:undefined));
  assert.equal(response.status,status);
  const body=await response.text();
  assert.ok(!body.includes('synthetic-server-only'));
  assert.ok(!body.includes('private PI details'));
  if(status!==200 || options.paused) assert.ok(!body.includes('download_url'));
  if(label==='unauthenticated') assert.equal(calls.length,0);
});
test('rejects caller supplied identity and unexpected method',async()=>{
  const {handler,calls}=fixture();
  assert.equal((await handler(new Request(`${origin}/functions/v1/mobile-update`,{method:'POST',headers:{Authorization:'Bearer employee-session'},body:'{"subject":"forged"}'}))).status,400);
  assert.equal((await handler(new Request(`${origin}/functions/v1/mobile-update`))).status,405);
  assert.equal(calls.length,0);
});
