// Deploy bound to a dedicated spreadsheet. Only this script writes the Transactions tab.
const HEADERS = ['Transaction ID','Event date UTC','Recorded date UTC','Type','Quantity','Payment','Revenue AUD','Fee AUD','Purchase cost AUD','Note','Corrects ID','Source JSON'];
const FIELDS = ['id','timestamp','recordedAt','type','quantity','payment','revenue','fee','cost','note','target'];
function canonical(event) {
  if (!event || typeof event !== 'object' || Array.isArray(event) || Object.keys(event).sort().join() !== FIELDS.slice().sort().join()) throw Error('Invalid fields');
  if (typeof event.id !== 'string' || !/^[A-Za-z0-9-]{10,100}$/.test(event.id)) throw Error('Invalid ID');
  if (!['single','deal','restock','missing','damaged','lost','undo'].includes(event.type) || !['cash','card','none'].includes(event.payment)) throw Error('Invalid type');
  if (typeof event.note !== 'string' || event.note.length > 500) throw Error('Invalid note');
  for (const name of ['quantity','revenue','fee','cost']) if (!Number.isSafeInteger(event[name]) || event[name] < 0 || event[name] > (name === 'quantity' ? 10000 : 10000000)) throw Error('Invalid amount');
  for (const name of ['timestamp','recordedAt']) if (!(name === 'timestamp' && event[name] === null) && (typeof event[name] !== 'string' || !Number.isFinite(Date.parse(event[name])))) throw Error('Invalid date');
  if (event.target !== null && (typeof event.target !== 'string' || !/^[A-Za-z0-9-]{10,100}$/.test(event.target))) throw Error('Invalid correction');
  const out={}; for (const field of FIELDS) out[field]=event[field];
  // Opening ingestion time differs across phone migrations, while its historical date remains unknown.
  if (event.id === 'opening-purchase-v1' || event.id === 'opening-missing-v1') out.recordedAt=null;
  return JSON.stringify(out);
}
function textCell(value) { return /^[\s]*[=+\-@]/.test(value) ? "'"+value : value; }
function prepare(events, existing) {
  const seen=new Map(existing), rows=[];
  if (!Array.isArray(events) || events.length < 1 || events.length > 100) throw Error('Invalid batch');
  for (const e of events) {
    const json=canonical(e);
    if (seen.has(e.id)) { if (seen.get(e.id)!==json) throw Error('Transaction ID conflict'); continue; }
    rows.push([e.id,e.timestamp||'',e.recordedAt,e.type,e.quantity,e.payment,e.revenue/100,e.fee/100,e.cost/100,textCell(e.note),e.target||'',json]);seen.set(e.id,json);
  }
  return rows;
}
function doPost(e) {
  let lock;
  try {
    if (!e || !e.postData || e.postData.contents.length > 150000) throw Error('Invalid request');
    const data=JSON.parse(e.postData.contents), props=PropertiesService.getScriptProperties();
    const secret=props.getProperty('SYNC_TOKEN');
    if (!secret || secret.length < 32 || data.token !== secret) throw Error('Unauthorized');
    lock=LockService.getScriptLock();lock.waitLock(20000);
    const book=SpreadsheetApp.openById(props.getProperty('SPREADSHEET_ID'));
    let sheet=book.getSheetByName('Transactions');
    if (!sheet) {sheet=book.insertSheet('Transactions');sheet.getRange(1,1,1,HEADERS.length).setValues([HEADERS]);sheet.setFrozenRows(1);sheet.getRange('G:I').setNumberFormat('0.00');sheet.hideColumns(12);}
    if (sheet.getRange(1,1,1,HEADERS.length).getValues()[0].join()!==HEADERS.join()) throw Error('Headers changed');
    const last=sheet.getLastRow();if(last>10001)throw Error('Ledger limit reached');
    const existing=new Map();
    if(last>1)for(const row of sheet.getRange(2,1,last-1,12).getValues()){if(existing.has(row[0]) || typeof row[11]!=='string')throw Error('Invalid existing rows');existing.set(row[0],row[11]);}
    const rows=prepare(data.events,existing);
    if(last+rows.length>10001)throw Error('Ledger limit reached');
    if(rows.length){const end=last+rows.length;if(end>sheet.getMaxRows())sheet.insertRowsAfter(sheet.getMaxRows(),end-sheet.getMaxRows());sheet.getRange(last+1,1,rows.length,12).setValues(rows);}
    SpreadsheetApp.flush();return response({ok:true,accepted:data.events.length});
  } catch(error) {return response({ok:false,error:'Upload rejected. Check token, deployment, headers and transaction conflicts.'});}
  finally {if(lock)lock.releaseLock();}
}
function response(value) {return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);}
