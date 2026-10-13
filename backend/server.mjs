import http from 'node:http';
import {DatabaseSync} from 'node:sqlite';
import {timingSafeEqual,createHash} from 'node:crypto';
import {mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {pathToFileURL} from 'node:url';

export class ApiError extends Error { constructor(status,message){super(message);this.status=status;} }
export function authenticate(provided,token){const a=Buffer.from(provided||''),b=Buffer.from(`Bearer ${token}`);if(a.length!==b.length||!timingSafeEqual(a,b))throw new ApiError(401,'Pair this phone using the backend access token.');}
export function configFromEnv(env=process.env){
  const key=env.STRIPE_SECRET_KEY||'',token=env.MONSTER_APP_TOKEN||'',location=env.STRIPE_LOCATION_ID||'';
  if(!/^sk_(test|live)_/.test(key)||token.length<32||!/^tml_\w+$/.test(location))throw new Error('Set STRIPE_SECRET_KEY, STRIPE_LOCATION_ID and a random MONSTER_APP_TOKEN (at least 32 characters).');
  const live=key.startsWith('sk_live_');if(live&&env.MONSTER_ALLOW_LIVE!=='true')throw new Error('Live mode is disabled. Complete test payments first, then explicitly set MONSTER_ALLOW_LIVE=true.');
  return {key,token,location,live,dbPath:env.MONSTER_DB_PATH||'./data/payments.db'};
}
export function stripeClient(key){return async(method,path,fields={},idempotencyKey)=>{
  const params=new URLSearchParams(fields);const headers={Authorization:`Bearer ${key}`};if(idempotencyKey)headers['Idempotency-Key']=idempotencyKey;
  const url=`https://api.stripe.com/v1${path}${method==='GET'&&params.size?'?'+params:''}`;
  if(method!=='GET')headers['Content-Type']='application/x-www-form-urlencoded';
  const response=await fetch(url,{method,headers,body:method==='GET'?undefined:params,signal:AbortSignal.timeout(25000)});
  const data=await response.json();if(!response.ok)throw new ApiError(502,'Stripe could not complete this request. Retry the same payment; do not start a second sale.');return data;
};}
export class Payments {
  constructor(config,stripe=stripeClient(config.key),now=()=>Date.now()){
    this.config=config;this.stripe=stripe;this.now=now;this.active=new Map();
    if(config.dbPath!==':memory:')mkdirSync(dirname(config.dbPath),{recursive:true});this.db=new DatabaseSync(config.dbPath);
    this.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS orders(id TEXT PRIMARY KEY,amount INTEGER NOT NULL,created_at INTEGER NOT NULL,intent_id TEXT,mode TEXT NOT NULL); CREATE TABLE IF NOT EXISTS refunds(id TEXT PRIMARY KEY,order_id TEXT NOT NULL REFERENCES orders(id),amount INTEGER NOT NULL,created_at INTEGER NOT NULL,refund_id TEXT UNIQUE);');
    const modes=this.db.prepare('SELECT DISTINCT mode FROM orders').all();if(modes.some(r=>r.mode!==(config.live?'live':'test'))){this.db.close();throw new Error('Use a separate payment database when switching Stripe mode. Keep the old database for recovery.');}
  }
  async order(id,amount){
    if(!/^[a-f0-9-]{36}$/.test(id)||!Number.isSafeInteger(amount)||amount<50||amount>10000000)throw new ApiError(400,'Invalid sale ID or amount. Minimum Stripe payment is AUD $0.50.');
    this.db.prepare('INSERT OR IGNORE INTO orders VALUES(?,?,?,NULL,?)').run(id,amount,this.now(),this.config.live?'live':'test');
    let row=this.db.prepare('SELECT * FROM orders WHERE id=?').get(id);if(row.amount!==amount)throw new ApiError(409,'The amount of a pending payment cannot be changed.');
    if(this.active.has(id))return this.active.get(id);
    const operation=(async()=>{
      if(!row.intent_id){
        // Freeze an uncertain creation before Stripe's idempotency retention window can expire.
        if(this.now()-row.created_at>20*60*60*1000)throw new ApiError(409,'This payment needs manual reconciliation in Stripe using its Monster sale ID. Do not create another payment.');
        const intent=await this.stripe('POST','/payment_intents',{amount:String(amount),currency:'aud','payment_method_types[]':'card_present',capture_method:'automatic','metadata[monster_sale_id]':id},'monster-sale-'+id);
        this.db.prepare('UPDATE orders SET intent_id=? WHERE id=?').run(intent.id,id);row={...row,intent_id:intent.id};
      }
      return this.stripe('GET','/payment_intents/'+row.intent_id,{'expand[]':'latest_charge.balance_transaction'});
    })();this.active.set(id,operation);try{return await operation;}finally{this.active.delete(id);}
  }
  validateIntent(intent,id,amount){if(intent.metadata?.monster_sale_id!==id||intent.amount!==amount||intent.currency!=='aud'||intent.livemode!==this.config.live)throw new ApiError(409,'Stripe payment does not match this sale or payment mode.');}
  summary(intent,id,amount){this.validateIntent(intent,id,amount);const transaction=intent.latest_charge?.balance_transaction;const fee=Number.isSafeInteger(transaction?.fee)?transaction.fee:null;if(fee!==null&&(fee<0||fee>amount||transaction.currency!=='aud'))throw new ApiError(409,'Unexpected Stripe fee or settlement currency; reconcile in Stripe.');return {id:intent.id,status:intent.status,amount,currency:'aud',live:this.config.live,fee,clientSecret:intent.client_secret};}
  refundSummary(refund,row,intent){
    if(refund.id!==row.refund_id||refund.payment_intent!==intent.id||refund.amount!==row.amount||refund.currency!=='aud'||refund.livemode!==this.config.live||!['pending','requires_action','succeeded','failed','canceled'].includes(refund.status))throw new ApiError(409,'Refund does not match its original sale or payment mode.');
    const transaction=refund.balance_transaction,fee=Number.isSafeInteger(transaction?.fee)?transaction.fee:null;
    if(fee!==null&&(Math.abs(fee)>10000000||transaction.currency!=='aud'))throw new ApiError(409,'Unexpected refund settlement fee/currency. Reconcile in Stripe.');
    if(!Number.isSafeInteger(refund.created)||refund.created<946684800)throw new ApiError(409,'Invalid Stripe refund timestamp.');
    return {requestId:row.id,saleId:row.order_id,id:refund.id,paymentIntent:intent.id,amount:row.amount,currency:'aud',live:this.config.live,status:refund.status,created:refund.created*1000,verifiedAt:this.now(),fee,failureReason:refund.failure_reason||null};
  }
  async refund(body,statusOnly=false){
    const {saleId,amount,refundId,refundAmount}=body;
    if(!/^[a-f0-9-]{36}$/.test(refundId)||!Number.isSafeInteger(refundAmount)||refundAmount<1||refundAmount>amount)throw new ApiError(400,'Invalid refund ID/amount.');
    const intent=await this.order(saleId,amount);this.validateIntent(intent,saleId,amount);if(intent.status!=='succeeded')throw new ApiError(409,'Only verified successful payments can be refunded.');
    this.db.prepare('INSERT OR IGNORE INTO refunds VALUES(?,?,?,?,NULL)').run(refundId,saleId,refundAmount,this.now());let row=this.db.prepare('SELECT * FROM refunds WHERE id=?').get(refundId);
    if(row.order_id!==saleId||row.amount!==refundAmount)throw new ApiError(409,'The sale and amount of a refund request cannot change.');
    const key='refund:'+refundId;if(this.active.has(key))return this.active.get(key);
    const operation=(async()=>{if(!row.refund_id){
      if(statusOnly){const all=await this.reconcileRefunds(intent,saleId);const found=all.find(r=>r.requestId===refundId);if(found)return found;throw new ApiError(409,'Refund creation is unresolved. Retry this same refund; do not make another request.');}
      if(this.now()-row.created_at>20*3600000)throw new ApiError(409,'Uncertain refund is too old to retry safely. Reconcile in Stripe by monster_refund_id before proceeding.');
      const result=await this.stripe('POST','/refunds',{payment_intent:intent.id,amount:String(refundAmount),'metadata[monster_sale_id]':saleId,'metadata[monster_refund_id]':refundId},'monster-refund-'+refundId);
      if(!/^re_[A-Za-z0-9]+$/.test(result.id))throw new ApiError(409,'Stripe returned an invalid refund ID.');
      this.db.prepare('UPDATE refunds SET refund_id=? WHERE id=?').run(result.id,refundId);row={...row,refund_id:result.id};
    }const result=await this.stripe('GET','/refunds/'+row.refund_id,{'expand[]':'balance_transaction'});return this.refundSummary(result,row,intent);})();
    this.active.set(key,operation);try{return await operation;}finally{this.active.delete(key);}
  }
  async reconcileRefunds(intent,saleId){
    let after;const result=[];
    for(let page=0;page<100;page++){
      const fields={payment_intent:intent.id,limit:'100','expand[]':'data.balance_transaction'};if(after)fields.starting_after=after;
      const list=await this.stripe('GET','/refunds',fields);if(!Array.isArray(list.data))throw new ApiError(502,'Invalid Stripe refund list.');
      for(const refund of list.data){
        if(!/^re_[A-Za-z0-9]+$/.test(refund.id)||refund.payment_intent!==intent.id)throw new ApiError(409,'Unmatched Stripe refund.');
        let row=this.db.prepare('SELECT * FROM refunds WHERE refund_id=?').get(refund.id);
        if(!row){const metadataId=refund.metadata?.monster_refund_id;const known=/^[a-f0-9-]{36}$/.test(metadataId||'')?this.db.prepare('SELECT * FROM refunds WHERE id=?').get(metadataId):null;
          if(known){if(known.order_id!==saleId||known.amount!==refund.amount||known.refund_id&&known.refund_id!==refund.id)throw new ApiError(409,'Refund metadata conflict.');this.db.prepare('UPDATE refunds SET refund_id=? WHERE id=?').run(refund.id,metadataId);row={...known,refund_id:refund.id};}
          else {const hash=createHash('sha256').update(refund.id).digest('hex');const id=[hash.slice(0,8),hash.slice(8,12),hash.slice(12,16),hash.slice(16,20),hash.slice(20,32)].join('-');this.db.prepare('INSERT INTO refunds VALUES(?,?,?,?,?)').run(id,saleId,refund.amount,this.now(),refund.id);row=this.db.prepare('SELECT * FROM refunds WHERE id=?').get(id);}
        }result.push(this.refundSummary(refund,row,intent));
      }
      if(!list.has_more)return result;if(list.data.length===0)throw new ApiError(502,'Stripe refund pagination failed.');after=list.data.at(-1).id;
    }throw new ApiError(409,'Refund history exceeds the reconciliation limit. No partial result was applied.');
  }
  async request(path,body){
    if(path==='/config')return {live:this.config.live,location:this.config.location};
    if(path==='/connection_token'){const t=await this.stripe('POST','/terminal/connection_tokens',{location:this.config.location});return {secret:t.secret};}
    if(path==='/refund'||path==='/refund_status')return this.refund(body,path==='/refund_status');
    if(!['/payment','/status','/cancel','/reconcile'].includes(path))throw new ApiError(404,'Endpoint not found.');
    const {saleId,amount}=body;let intent=await this.order(saleId,amount);this.validateIntent(intent,saleId,amount);
    if(path==='/reconcile'){const payment=this.summary(intent,saleId,amount);const refunds=await this.reconcileRefunds(intent,saleId);delete payment.clientSecret;return {payment,refunds};}
    if(path==='/cancel'&&intent.status!=='canceled'){
      if(['succeeded','processing','requires_capture'].includes(intent.status))throw new ApiError(409,'Payment may already be paid. Check status; do not collect another payment.');
      intent=await this.stripe('POST','/payment_intents/'+intent.id+'/cancel',{},'monster-cancel-'+saleId);
    }
    return this.summary(intent,saleId,amount);
  }
  close(){this.db.close();}
}
export function createServer(config,payments=new Payments(config)){
  const server=http.createServer(async(req,res)=>{
    res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
    try{
      if(req.method==='GET'&&req.url==='/health'){res.end('{"ok":true}');return;}
      if(req.method!=='POST')throw new ApiError(405,'POST required.');authenticate(req.headers.authorization,config.token);
      if(req.headers.origin)throw new ApiError(403,'Browser requests are not supported.');
      let data='';for await(const chunk of req){data+=chunk;if(Buffer.byteLength(data)>2048)throw new ApiError(413,'Request too large.');}
      let body;try{body=JSON.parse(data||'{}');}catch{throw new ApiError(400,'Invalid JSON.');}
      if(body===null||typeof body!=='object'||Array.isArray(body))throw new ApiError(400,'Invalid request.');
      res.end(JSON.stringify(await payments.request(req.url,body)));
    }catch(e){res.statusCode=e.status||503;res.end(JSON.stringify({error:e.status?e.message:'Payment service unavailable. Retry the same sale.'}));}
  });server.requestTimeout=30000;server.headersTimeout=10000;return server;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){const config=configFromEnv();createServer(config).listen(Number(process.env.PORT||8080),'0.0.0.0',()=>console.log('Monster payment backend started ('+(config.live?'live':'test')+' mode).'));}
