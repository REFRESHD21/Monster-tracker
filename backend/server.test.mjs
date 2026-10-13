import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Payments,authenticate,configFromEnv} from './server.mjs';
const id='10000000-0000-4000-8000-000000000001';
function fixture(path=':memory:'){
 const intents=new Map();let creates=0,lose=false,status='requires_payment_method';
 const stripe=async(method,path,fields,key)=>{
  if(path==='/payment_intents'){let pi=intents.get(key);if(!pi){creates++;pi={id:'pi_1',amount:Number(fields.amount),currency:'aud',metadata:{monster_sale_id:fields['metadata[monster_sale_id]']},livemode:false,client_secret:'test_secret',status};intents.set(key,pi);}if(lose){lose=false;throw new Error('lost response');}return pi;}
  const pi=[...intents.values()][0];if(path.endsWith('/cancel'))pi.status='canceled';return {...pi,status:pi.status==='canceled'?'canceled':status};
 };
 const config={key:'sk_test_example',token:'x'.repeat(40),location:'tml_test',live:false,dbPath:path};
 return {config,stripe,p:new Payments(config,stripe),get creates(){return creates;},lost(){lose=true;},paid(){status='succeeded';}};
}
test('authentication rejects missing/wrong tokens',()=>{assert.throws(()=>authenticate('', 'x'.repeat(40)),/Pair/);authenticate('Bearer '+'x'.repeat(40),'x'.repeat(40));});
test('live mode requires explicit activation',()=>assert.throws(()=>configFromEnv({STRIPE_SECRET_KEY:'sk_live_example',MONSTER_APP_TOKEN:'x'.repeat(40),STRIPE_LOCATION_ID:'tml_test'}),/Live mode is disabled/));
test('lost create response reuses one Stripe intent',async()=>{const f=fixture();f.lost();await assert.rejects(f.p.request('/payment',{saleId:id,amount:350}));const r=await f.p.request('/payment',{saleId:id,amount:350});assert.equal(r.id,'pi_1');assert.equal(f.creates,1);f.p.close();});
test('restart reuses saved intent and forbids changed amount',async()=>{const dir=mkdtempSync(join(tmpdir(),'monster-pay-'));const f=fixture(join(dir,'db'));await f.p.request('/payment',{saleId:id,amount:350});f.p.close();const p=new Payments(f.config,f.stripe);await p.request('/status',{saleId:id,amount:350});assert.equal(f.creates,1);await assert.rejects(p.request('/payment',{saleId:id,amount:600}),/amount/);p.close();rmSync(dir,{recursive:true});});
test('concurrent retries share creation',async()=>{const f=fixture();await Promise.all([f.p.request('/payment',{saleId:id,amount:350}),f.p.request('/payment',{saleId:id,amount:350})]);assert.equal(f.creates,1);f.p.close();});
test('paid sale cannot be discarded as canceled',async()=>{const f=fixture();await f.p.request('/payment',{saleId:id,amount:350});f.paid();await assert.rejects(f.p.request('/cancel',{saleId:id,amount:350}),/already be paid/);f.p.close();});
test('uncertain creation freezes before idempotency expires',async()=>{const f=fixture();f.lost();await assert.rejects(f.p.order(id,350));f.p.now=()=>Date.now()+21*3600000;await assert.rejects(f.p.order(id,350),/manual reconciliation/);assert.equal(f.creates,1);f.p.close();});
test('test and live databases cannot be mixed',async()=>{const dir=mkdtempSync(join(tmpdir(),'monster-mode-'));const f=fixture(join(dir,'db'));await f.p.order(id,350);f.p.close();assert.throws(()=>new Payments({...f.config,live:true},f.stripe),/separate payment database/);rmSync(dir,{recursive:true});});
test('fee stays unknown until settlement data exists',async()=>{const f=fixture();const r=await f.p.request('/payment',{saleId:id,amount:350});assert.equal(r.fee,null);assert.throws(()=>f.p.summary({metadata:{monster_sale_id:id},amount:350,currency:'aud',livemode:true},id,350),/does not match/);f.p.close();});
