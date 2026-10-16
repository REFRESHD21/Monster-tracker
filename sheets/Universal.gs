// Separate receiver tab: does not modify the existing 1.6.3 Transactions ledger.
const UNIVERSAL_HEADERS=['Business ID','Record ID','Kind','Recorded UTC','Source JSON'];
function universalCanonical(value) {
  if(value===null||typeof value==='boolean'||typeof value==='string')return JSON.stringify(value);
  if(typeof value==='number'){if(!Number.isSafeInteger(value))throw Error('Invalid number');return String(value);}
  if(Array.isArray(value))return '['+value.map(universalCanonical).join(',')+']';
  if(typeof value!=='object')throw Error('Invalid record');
  return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+universalCanonical(value[k])).join(',')+'}';
}
function universalPrepare(businessId,records,existing) {
  if(typeof businessId!=='string'||!/^[-A-Za-z0-9]{10,100}$/.test(businessId)||!Array.isArray(records)||records.length<1||records.length>50)throw Error('Invalid batch');
  const seen=new Map(existing), rows=[];
  for(const r of records){
    if(!r||Object.keys(r).sort().join()!=='body,id,kind'||typeof r.id!=='string'||!/^[-A-Za-z0-9]{5,240}$/.test(r.id)||typeof r.kind!=='string'||!/^[-a-z]+$/.test(r.kind)||!r.body||Array.isArray(r.body))throw Error('Invalid record');
    const json=universalCanonical(r),key=businessId+'|'+r.id;
    if(json.length>45000)throw Error('Record too large');
    if(seen.has(key)){if(seen.get(key)!==json)throw Error('Record conflict');continue;}
    rows.push([businessId,r.id,r.kind,new Date().toISOString(),json]);seen.set(key,json);
  }
  return rows;
}
function doPost(e) {
  let lock;
  try {
    if(!e?.postData||e.postData.contents.length>2000000)throw Error('Request too large');
    const data=JSON.parse(e.postData.contents),props=PropertiesService.getScriptProperties(),secret=props.getProperty('SYNC_TOKEN');
    if(!secret||secret.length<32||data.token!==secret)throw Error('Unauthorized');
    lock=LockService.getScriptLock();lock.waitLock(20000);
    const book=SpreadsheetApp.openById(props.getProperty('SPREADSHEET_ID'));
    let sheet=book.getSheetByName('UniversalRecords');
    if(!sheet){sheet=book.insertSheet('UniversalRecords');sheet.getRange(1,1,1,5).setValues([UNIVERSAL_HEADERS]);sheet.setFrozenRows(1);}
    if(sheet.getRange(1,1,1,5).getValues()[0].join()!==UNIVERSAL_HEADERS.join())throw Error('Changed headers');
    const last=sheet.getLastRow();if(last>50001)throw Error('Record limit');
    const existing=new Map();if(last>1)for(const row of sheet.getRange(2,1,last-1,5).getValues()){const key=row[0]+'|'+row[1];if(existing.has(key))throw Error('Duplicate existing record');existing.set(key,row[4]);}
    const rows=universalPrepare(data.businessId,data.records,existing);
    if(last+rows.length>50001)throw Error('Record limit');
    if(rows.length){if(last+rows.length>sheet.getMaxRows())sheet.insertRowsAfter(sheet.getMaxRows(),last+rows.length-sheet.getMaxRows());sheet.getRange(last+1,1,rows.length,5).setNumberFormat('@').setValues(rows);}
    SpreadsheetApp.flush();return universalResponse({ok:true,accepted:data.records.length});
  }catch(_){return universalResponse({ok:false,error:'Upload rejected. Check deployment, token, headers and conflicting records.'});}
  finally{if(lock)lock.releaseLock();}
}
function universalResponse(data){return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(ContentService.MimeType.JSON);}
