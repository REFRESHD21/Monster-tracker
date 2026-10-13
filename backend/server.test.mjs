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

const refundId='20000000-0000-4000-8000-000000000001';
function refundFixture(dbPath=':memory:'){
 const refunds=new Map();let creates=0,lost=false,status='succeeded';
 const intent={id:'pi_paid',amount:600,currency:'aud',metadata:{monster_sale_id:id},livemode:false,client_secret:'secret',status:'succeeded',latest_charge:{balance_transaction:{fee:25,currency:'aud'}}};
 const stripe=async(method,path,fields={},key)=>{
  if(path==='/payment_intents'||path==='/payment_intents/pi_paid')return {...intent};
  if(path==='/refunds'&&method==='POST'){let r=refunds.get(key);if(!r){creates++;r={id:'re_'+creates,payment_intent:intent.id,amount:Number(fields.amount),currency:'aud',livemode:false,status,created:Math.floor(Date.now()/1000),metadata:{monster_refund_id:fields['metadata[monster_refund_id]']},balance_transaction:{fee:0,currency:'aud'}};refunds.set(key,r);}if(lost){lost=false;throw new Error('lost refund response');}return {...r,status};}
  if(path==='/refunds'&&method==='GET')return {data:[...refunds.values()].map(r=>({...r,status})),has_more:false};
  if(path.startsWith('/refunds/'))return {...[...refunds.values()].find(r=>r.id===path.slice(9)),status};
  throw new Error('Unexpected Stripe request '+path);
 };
 const config={key:'sk_test_example',token:'x'.repeat(40),location:'tml_test',live:false,dbPath};
 return {p:new Payments(config,stripe),config,stripe,refunds,get creates(){return creates;},lost(){lost=true;},status(s){status=s;},intent};
}
const refundBody={saleId:id,amount:600,refundId,refundAmount:300};
test('refund lost response retries one durable Stripe refund',async()=>{const f=refundFixture();f.lost();await assert.rejects(f.p.request('/refund',refundBody));const r=await f.p.request('/refund',refundBody);assert.equal(r.amount,300);assert.equal(r.status,'succeeded');assert.equal(f.creates,1);f.p.close();});
test('concurrent refund taps use the same refund ID',async()=>{const f=refundFixture();await Promise.all([f.p.request('/refund',refundBody),f.p.request('/refund',refundBody)]);assert.equal(f.creates,1);f.p.close();});
test('refund amount and original sale cannot change on retry',async()=>{const f=refundFixture();await f.p.request('/refund',refundBody);await assert.rejects(f.p.request('/refund',{...refundBody,refundAmount:600}),/cannot change/);assert.equal(f.creates,1);f.p.close();});
test('refund restart retrieves same provider refund',async()=>{const dir=mkdtempSync(join(tmpdir(),'monster-refund-'));const f=refundFixture(join(dir,'db'));await f.p.request('/refund',refundBody);f.p.close();const second=new Payments(f.config,f.stripe);await second.request('/refund_status',refundBody);assert.equal(f.creates,1);second.close();rmSync(dir,{recursive:true});});
test('pending and failed refunds are reported without claiming success',async()=>{const f=refundFixture();f.status('pending');assert.equal((await f.p.request('/refund',refundBody)).status,'pending');f.status('failed');assert.equal((await f.p.request('/refund_status',refundBody)).status,'failed');f.p.close();});
test('refund reconciliation adopts lost creation before repeating request',async()=>{const f=refundFixture();f.lost();await assert.rejects(f.p.request('/refund',refundBody));f.p.now=()=>Date.now()+21*3600000;await assert.rejects(f.p.request('/refund',refundBody),/too old/);const r=await f.p.request('/reconcile',{saleId:id,amount:600});assert.equal(r.refunds[0].requestId,refundId);assert.equal(r.refunds[0].id,'re_1');assert.equal(f.creates,1);assert.equal(r.payment.clientSecret,undefined);f.p.close();});
test('refund fee is actual and original processing fee is retained',async()=>{const f=refundFixture();const r=await f.p.request('/refund',refundBody);assert.equal(r.fee,0);const payment=await f.p.request('/status',{saleId:id,amount:600});assert.equal(payment.fee,25);f.p.close();});
test('refund validation rejects invalid IDs amounts mode and original payment',async()=>{const f=refundFixture();await assert.rejects(f.p.request('/refund',{...refundBody,refundAmount:601}),/Invalid refund/);await assert.rejects(f.p.request('/refund',{...refundBody,refundId:'bad'}),/Invalid refund/);f.intent.status='requires_payment_method';await assert.rejects(f.p.request('/refund',refundBody),/successful payments/);f.p.close();});
