///|
/// Node.js production adapter. MoonBit prepares verified plans; SQLite
/// atomically commits idempotency, events, deliveries, and worker leases.
extern "js" fn run_gateway_runtime(
  port : Int,
  data_dir : String,
  handler : (String, String, String, Int64) -> String,
  publisher : (String, String, String, String, String) -> String,
  signer : (String, String, String, Int64, String, String, String, String) -> String,
  decision : (Int, Int, String, String) -> String,
  acquire : (String, Int64) -> Bool,
  cancel : (String) -> Unit,
  complete : (String, Int, Int64, Int64) -> Unit,
  circuit_state : (String, Int64) -> String,
  metrics : () -> String,
  outbound_catalog : String,
  dashboard : String,
) -> Unit =
  #| function(port, dataDir, handler, publisher, signer, decision, acquire, cancel, complete, circuitState, metrics, outboundCatalog, dashboard) {
  #|   const http = require("node:http");
  #|   const fs = require("node:fs");
  #|   const path = require("node:path");
  #|   const crypto = require("node:crypto");
  #|   const performance = require("node:perf_hooks").performance;
  #|   let DatabaseSync;
  #|   try { ({DatabaseSync} = require("node:sqlite")); }
  #|   catch (error) { throw new Error("HookLab Gateway requires Node.js 24+ for SQLite: " + String(error)); }
  #|   const root = path.resolve(dataDir);
  #|   fs.mkdirSync(root, {recursive: true});
  #|   const databasePath = path.join(root, "hooklab.sqlite");
  #|   const legacyStatePath = path.join(root, "state.json");
  #|   const db = new DatabaseSync(databasePath);
  #|   db.exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA synchronous=FULL;");
  #|   db.exec("CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL)");
  #|   db.exec("CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,source TEXT NOT NULL,application_id TEXT,provider TEXT NOT NULL,event_type TEXT NOT NULL,delivery_id TEXT,idempotency_key TEXT,fingerprint TEXT,body TEXT NOT NULL,redacted_body TEXT NOT NULL,headers_json TEXT NOT NULL DEFAULT '[]',received_at INTEGER NOT NULL,targets_json TEXT NOT NULL DEFAULT '[]',outputs_json TEXT NOT NULL DEFAULT '[]',UNIQUE(provider,delivery_id),UNIQUE(source,application_id,idempotency_key))");
  #|   db.exec("CREATE TABLE IF NOT EXISTS deliveries(id TEXT PRIMARY KEY,event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,target TEXT NOT NULL,endpoint_id TEXT,subscription_id TEXT,key_id TEXT,payload TEXT,state TEXT NOT NULL CHECK(state IN ('pending','scheduled','in_flight','delivered','dead_lettered','cancelled')),attempt INTEGER NOT NULL DEFAULT 0,next_attempt_at INTEGER NOT NULL,last_status INTEGER,last_error TEXT,worker_id TEXT,lease_token TEXT,leased_until INTEGER,version INTEGER NOT NULL DEFAULT 0,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL)");
  #|   db.exec("CREATE INDEX IF NOT EXISTS deliveries_due_idx ON deliveries(state,next_attempt_at)");
  #|   db.exec("CREATE INDEX IF NOT EXISTS deliveries_event_idx ON deliveries(event_id)");
  #|   db.exec("CREATE INDEX IF NOT EXISTS deliveries_lease_idx ON deliveries(state,leased_until)");
  #|   db.prepare("INSERT INTO metadata(key,value) VALUES('schema_version','1') ON CONFLICT(key) DO UPDATE SET value=excluded.value").run();
  #|   const transaction = fn => {
  #|     db.exec("BEGIN IMMEDIATE");
  #|     try { const value = fn(); db.exec("COMMIT"); return value; }
  #|     catch (error) { try { db.exec("ROLLBACK"); } catch (_) {} throw error; }
  #|   };
  #|   const parseArray = value => {
  #|     try { const parsed = JSON.parse(value || "[]"); return Array.isArray(parsed) ? parsed : []; }
  #|     catch (_) { return []; }
  #|   };
  #|   const hash = value => crypto.createHash("sha256").update(value).digest("hex").slice(0, 24);
  #|   const workerId = "worker:" + process.pid + ":" + crypto.randomUUID();
  #|   const requestedLeaseMs = Number(process.env.HOOKLAB_LEASE_MS || 30000);
  #|   const leaseMs = Number.isFinite(requestedLeaseMs) ? Math.max(1000, Math.min(300000, Math.trunc(requestedLeaseMs))) : 30000;
  #|   const now = () => Date.now();
  #|   const insertEvent = db.prepare("INSERT INTO events(id,source,application_id,provider,event_type,delivery_id,idempotency_key,fingerprint,body,redacted_body,headers_json,received_at,targets_json,outputs_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
  #|   const insertDelivery = db.prepare("INSERT INTO deliveries(id,event_id,target,endpoint_id,subscription_id,key_id,payload,state,attempt,next_attempt_at,last_status,last_error,worker_id,lease_token,leased_until,version,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
  #|   const importLegacyState = () => {
  #|     if (!fs.existsSync(legacyStatePath)) return;
  #|     if (db.prepare("SELECT value FROM metadata WHERE key='legacy_state_imported'").get()) return;
  #|     if (Number(db.prepare("SELECT COUNT(*) AS count FROM events").get().count) > 0) return;
  #|     let legacy;
  #|     try { legacy = JSON.parse(fs.readFileSync(legacyStatePath, "utf8")); }
  #|     catch (error) { throw new Error("Refusing to start because legacy state.json is unreadable: " + String(error)); }
  #|     if (!legacy || legacy.version !== 1 || !Array.isArray(legacy.events) || !Array.isArray(legacy.deliveries)) {
  #|       throw new Error("Refusing to start because legacy state.json has an unsupported shape.");
  #|     }
  #|     transaction(() => {
  #|       for (const event of legacy.events) {
  #|         insertEvent.run(event.id, "ingress", null, event.provider || "unknown", event.eventType || "unknown", event.deliveryId || null, null, null, event.body || "", event.redactedBody || "", JSON.stringify(event.headers || []), Number(event.receivedAt || now()), JSON.stringify(event.targets || []), JSON.stringify(event.outputs || []));
  #|       }
  #|       for (const item of legacy.deliveries) {
  #|         const recovered = item.state === "in_flight";
  #|         insertDelivery.run(item.id, item.eventId, item.target, item.endpointId || null, item.subscriptionId || null, item.keyId || null, typeof item.payload === "string" ? item.payload : null, recovered ? "scheduled" : item.state, Number(item.attempt || 0), recovered ? now() : Number(item.nextAttemptAt || now()), item.lastStatus ?? null, recovered ? "recovered from legacy in-flight state" : (item.lastError || null), null, null, null, 0, Number(item.createdAt || now()), now());
  #|       }
  #|       db.prepare("INSERT INTO metadata(key,value) VALUES('legacy_state_imported',?)").run(String(now()));
  #|     });
  #|   };
  #|   importLegacyState();
  #|   const json = (res, status, value) => {
  #|     const body = JSON.stringify(value);
  #|     res.writeHead(status, {"content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(body), "cache-control": "no-store", "x-content-type-options": "nosniff"});
  #|     res.end(body);
  #|   };
  #|   const safeHeaders = headers => Object.entries(headers).map(([name, value]) => {
  #|     const lower = name.toLowerCase();
  #|     const sensitive = lower === "authorization" || lower === "cookie" || lower === "set-cookie" || lower === "x-api-key" || lower.includes("signature");
  #|     return {name, value: sensitive ? "[REDACTED]" : String(Array.isArray(value) ? value.join(",") : value ?? "")};
  #|   });
  #|   const decodePathSegment = value => {
  #|     try { return {ok:true,value:decodeURIComponent(value)}; }
  #|     catch (_) { return {ok:false,value:""}; }
  #|   };
  #|   const isLoopbackName = value => value === "127.0.0.1" || value === "localhost";
  #|   const hasAllowedHost = req => {
  #|     const value=String(req.headers.host||"").toLowerCase();
  #|     return value==="127.0.0.1"||value==="localhost"||value==="127.0.0.1:"+port||value==="localhost:"+port;
  #|   };
  #|   const hasAllowedManagementOrigin = req => {
  #|     const fetchSite=String(req.headers["sec-fetch-site"]||"").toLowerCase();
  #|     if(fetchSite&&fetchSite!=="same-origin")return false;
  #|     const origin=String(req.headers.origin||"");
  #|     if(!origin)return true;
  #|     try { const parsed=new URL(origin);return parsed.protocol==="http:"&&isLoopbackName(parsed.hostname.toLowerCase())&&String(parsed.port||"80")===String(port); }
  #|     catch(_){return false;}
  #|   };
  #|   const handlerHeaders = headers => JSON.stringify(Object.entries(headers).map(([name, value]) => ({name, value: String(Array.isArray(value) ? value.join(",") : value ?? "")})));
  #|   const bodyOf = (req, res) => new Promise(resolve => {
  #|     const chunks = [];
  #|     let size = 0;
  #|     let tooLarge = false;
  #|     req.on("data", chunk => {
  #|       size += chunk.length;
  #|       if (size > 1024 * 1024) tooLarge = true; else chunks.push(chunk);
  #|     });
  #|     req.on("end", () => {
  #|       if (tooLarge) { json(res, 413, {error: "payload_too_large", maxBytes: 1048576}); resolve(null); }
  #|       else {
  #|         try { resolve(new TextDecoder("utf-8", {fatal:true}).decode(Buffer.concat(chunks))); }
  #|         catch (_) { json(res, 422, {error:"invalid_utf8"}); resolve(null); }
  #|       }
  #|     });
  #|     req.on("error", () => resolve(null));
  #|   });
  #|   const eventRow = id => db.prepare("SELECT * FROM events WHERE id=?").get(id);
  #|   const deliveryRow = id => db.prepare("SELECT * FROM deliveries WHERE id=?").get(id);
  #|   const publicEvent = event => ({id: event.id,source: event.source,applicationId: event.application_id,provider: event.provider,eventType: event.event_type,deliveryId: event.delivery_id,redactedBody: event.redacted_body,receivedAt: event.received_at,targets: parseArray(event.targets_json)});
  #|   const publicDelivery = item => ({id:item.id,eventId:item.event_id,endpointId:item.endpoint_id,subscriptionId:item.subscription_id,target:item.target,state:item.state,circuitState:circuitState(item.target,BigInt(now())),attempt:item.attempt,nextAttemptAt:item.next_attempt_at,lastStatus:item.last_status,lastError:item.last_error,leaseOwner:item.state==="in_flight"?item.worker_id:null,leasedUntil:item.state==="in_flight"?item.leased_until:null,version:item.version,updatedAt:item.updated_at});
  #|   const stats = () => {
  #|     const result = {events:Number(db.prepare("SELECT COUNT(*) AS count FROM events").get().count),pending:0,scheduled:0,in_flight:0,delivered:0,dead_lettered:0,cancelled:0};
  #|     for (const row of db.prepare("SELECT state,COUNT(*) AS count FROM deliveries GROUP BY state").all()) if (Object.hasOwn(result,row.state)) result[row.state]=Number(row.count);
  #|     return result;
  #|   };
  #|   function addDeliveries(eventId, deliveries, createdAt) {
  #|     for (const work of deliveries) insertDelivery.run(work.id,eventId,work.target,work.endpoint_id||null,work.subscription_id||null,work.key_id||null,typeof work.payload==="string"?work.payload:null,"pending",0,createdAt,null,null,null,null,null,0,createdAt,createdAt);
  #|   }
  #|   function enqueueReplay(event) {
  #|     const createdAt=now();
  #|     const outputs=parseArray(event.outputs_json);
  #|     transaction(() => {
  #|       let sequence=Number(db.prepare("SELECT COUNT(*) AS count FROM deliveries").get().count);
  #|       for (const output of outputs) {
  #|         sequence++;
  #|         const id="delivery:"+hash(event.id+"\n"+(output.subscription_id||output.target)+"\n"+createdAt+"\n"+sequence);
  #|         insertDelivery.run(id,event.id,output.target,output.endpoint_id||null,output.subscription_id||null,output.key_id||null,typeof output.payload==="string"?output.payload:null,"pending",0,createdAt,null,"manual replay",null,null,null,0,createdAt,createdAt);
  #|       }
  #|     });
  #|     return outputs.length;
  #|   }
  #|   function recoverExpiredLeases(at) {
  #|     return db.prepare("UPDATE deliveries SET state='scheduled',next_attempt_at=?,last_error='worker lease expired; delivery reclaimed',worker_id=NULL,lease_token=NULL,leased_until=NULL,version=version+1,updated_at=? WHERE state='in_flight' AND leased_until IS NOT NULL AND leased_until<=?").run(at,at,at);
  #|   }
  #|   function claim(item,at) {
  #|     const token=crypto.randomUUID();
  #|     const result=transaction(() => db.prepare("UPDATE deliveries SET state='in_flight',attempt=attempt+1,worker_id=?,lease_token=?,leased_until=?,version=version+1,updated_at=? WHERE id=? AND version=? AND state IN ('pending','scheduled') AND next_attempt_at<=?").run(workerId,token,at+leaseMs,at,item.id,item.version,at));
  #|     return Number(result.changes)===1?deliveryRow(item.id):null;
  #|   }
  #|   async function deliver(item) {
  #|     const startedAt=performance.now();
  #|     let circuitOutcome=0;
  #|     const heartbeatMs=Math.max(250,Math.floor(leaseMs/3));
  #|     const leaseHeartbeat=setInterval(()=>{
  #|       const renewedAt=now();
  #|       try { const renewed=db.prepare("UPDATE deliveries SET leased_until=?,updated_at=? WHERE id=? AND state='in_flight' AND worker_id=? AND lease_token=? AND version=? AND leased_until IS NOT NULL AND leased_until>?").run(renewedAt+leaseMs,renewedAt,item.id,workerId,item.lease_token,item.version,renewedAt);if(Number(renewed.changes)!==1)clearInterval(leaseHeartbeat); }
  #|       catch (error) { console.error("HookLab lease renewal failed",error); }
  #|     },heartbeatMs);
  #|     try {
  #|       const event=eventRow(item.event_id);
  #|       let status=0,retryAfter="",transportError="";
  #|       try {
  #|         if (!event) throw new Error("event payload is missing");
  #|         const payload=typeof item.payload==="string"?item.payload:event.body;
  #|         const headers={"content-type":"application/json","x-hooklab-event-id":event.id,"x-hooklab-delivery-id":item.id,"x-hooklab-event-type":event.event_type};
  #|         if (item.endpoint_id) {
  #|           const timestamp=Math.floor(now()/1000);
  #|           const signature=signer(item.endpoint_id,item.target,item.key_id||"",BigInt(timestamp),item.id,event.id,event.event_type,payload);
  #|           if (!signature) throw new Error("outbound signing secret is unavailable");
  #|           headers["x-hooklab-timestamp"]=String(timestamp);
  #|           headers["x-hooklab-key-id"]=item.key_id||"";
  #|           headers["x-hooklab-signature"]=signature;
  #|         }
  #|         const response=await fetch(item.target,{method:"POST",redirect:"manual",headers,body:payload,signal:AbortSignal.timeout(15000)});
  #|         status=response.status;
  #|         retryAfter=response.headers.get("retry-after")||"";
  #|         if (response.body) await response.body.cancel();
  #|       } catch (error) { transportError=String(error); }
  #|       circuitOutcome=transportError||status===408||status===425||status===429||status>=500?2:status>=200&&status<300?1:0;
  #|       let result;
  #|       try { result=JSON.parse(decision(item.attempt,status,retryAfter,transportError)); }
  #|       catch (error) { result={decision:"dead_letter",reason:"invalid MoonBit delivery decision: "+String(error)}; }
  #|       const updatedAt=now();
  #|       transaction(() => {
  #|         const current=deliveryRow(item.id);
  #|         if (!current||current.state!=="in_flight"||current.worker_id!==workerId||current.lease_token!==item.lease_token||current.version!==item.version||current.leased_until<=updatedAt) return;
  #|         if (result.decision==="success") db.prepare("UPDATE deliveries SET state='delivered',last_status=?,last_error=NULL,worker_id=NULL,lease_token=NULL,leased_until=NULL,version=version+1,updated_at=? WHERE id=? AND worker_id=? AND lease_token=? AND version=?").run(status||null,updatedAt,item.id,workerId,item.lease_token,item.version);
  #|         else if (result.decision==="retry") db.prepare("UPDATE deliveries SET state='scheduled',next_attempt_at=?,last_status=?,last_error=?,worker_id=NULL,lease_token=NULL,leased_until=NULL,version=version+1,updated_at=? WHERE id=? AND worker_id=? AND lease_token=? AND version=?").run(updatedAt+Number(result.delay_ms||0),status||null,transportError||("HTTP "+status),updatedAt,item.id,workerId,item.lease_token,item.version);
  #|         else db.prepare("UPDATE deliveries SET state='dead_lettered',last_status=?,last_error=?,worker_id=NULL,lease_token=NULL,leased_until=NULL,version=version+1,updated_at=? WHERE id=? AND worker_id=? AND lease_token=? AND version=?").run(status||null,result.reason||transportError||("HTTP "+status),updatedAt,item.id,workerId,item.lease_token,item.version);
  #|       });
  #|     } finally { clearInterval(leaseHeartbeat); complete(item.target,circuitOutcome,BigInt(now()),BigInt(Math.max(0,Math.round(performance.now()-startedAt)))); }
  #|   }
  #|   let scanning=false;
  #|   function pump() {
  #|     if (scanning) return;
  #|     scanning=true;
  #|     try {
  #|       const at=now();
  #|       transaction(() => recoverExpiredLeases(at));
  #|       const candidates=db.prepare("SELECT * FROM deliveries WHERE state IN ('pending','scheduled') AND next_attempt_at<=? ORDER BY created_at,id LIMIT 64").all(at);
  #|       for (const item of candidates) {
  #|         if (!acquire(item.target,BigInt(at))) continue;
  #|         let claimed=null;
  #|         try { claimed=claim(item,at); } catch (error) { cancel(item.target); throw error; }
  #|         if (!claimed) { cancel(item.target); continue; }
  #|         void deliver(claimed).catch(error=>console.error(error));
  #|       }
  #|     } finally { scanning=false; }
  #|   }
  #|   const pumpTimer=setInterval(()=>{try{pump();}catch(error){console.error(error);}},250);
  #|   const handleRequest=async(req,res)=>{
  #|     const url=new URL(req.url||"/","http://127.0.0.1");
  #|     if(!hasAllowedHost(req))return json(res,421,{error:"untrusted_host"});
  #|     if(req.method==="GET"&&url.pathname==="/"){res.writeHead(200,{"content-type":"text/html; charset=utf-8","cache-control":"no-store","x-content-type-options":"nosniff"});return res.end(dashboard);}
  #|     if(req.method==="GET"&&url.pathname==="/health")return json(res,200,{status:"ok",storage:"sqlite",schemaVersion:1,workerId,...stats()});
  #|     if(req.method==="GET"&&url.pathname==="/api/stats")return json(res,200,stats());
  #|     if(req.method==="GET"&&url.pathname==="/api/metrics"){try{return json(res,200,JSON.parse(metrics()));}catch(_){return json(res,500,{error:"metrics_unavailable"});}}
  #|     if(req.method==="GET"&&url.pathname==="/api/events")return json(res,200,db.prepare("SELECT * FROM events ORDER BY received_at,id").all().map(publicEvent));
  #|     if(req.method==="GET"&&url.pathname==="/api/deliveries")return json(res,200,db.prepare("SELECT * FROM deliveries ORDER BY created_at,id").all().map(publicDelivery));
  #|     if(req.method==="GET"&&url.pathname==="/api/outbound/catalog"){try{return json(res,200,JSON.parse(outboundCatalog));}catch(_){return json(res,500,{error:"outbound_catalog_unavailable"});}}
  #|     const retryMatch=url.pathname.match(/^\/api\/deliveries\/([^/]+)\/retry$/);
  #|     if(req.method==="POST"&&retryMatch){
  #|       if(!hasAllowedManagementOrigin(req))return json(res,403,{error:"cross_origin_management_request"});
  #|       const decoded=decodePathSegment(retryMatch[1]);if(!decoded.ok)return json(res,400,{error:"invalid_path_encoding"});
  #|       const id=decoded.value,item=deliveryRow(id);
  #|       if(!item)return json(res,404,{error:"delivery_not_found"});
  #|       if(item.state!=="dead_lettered")return json(res,409,{error:"invalid_transition",state:item.state});
  #|       const at=now();
  #|       transaction(()=>db.prepare("UPDATE deliveries SET state='pending',attempt=0,next_attempt_at=?,last_status=NULL,last_error='manual retry',worker_id=NULL,lease_token=NULL,leased_until=NULL,version=version+1,updated_at=? WHERE id=? AND state='dead_lettered'").run(at,at,id));
  #|       return json(res,202,publicDelivery(deliveryRow(id)));
  #|     }
  #|     const replayMatch=url.pathname.match(/^\/api\/events\/([^/]+)\/replay$/);
  #|     if(req.method==="POST"&&replayMatch){if(!hasAllowedManagementOrigin(req))return json(res,403,{error:"cross_origin_management_request"});const decoded=decodePathSegment(replayMatch[1]);if(!decoded.ok)return json(res,400,{error:"invalid_path_encoding"});const event=eventRow(decoded.value);if(!event)return json(res,404,{error:"event_not_found"});return json(res,202,{eventId:event.id,replayed:enqueueReplay(event)});}
  #|     const publishMatch=url.pathname.match(/^\/api\/outbound\/applications\/([^/]+)\/events\/([^/]+)$/);
  #|     if(req.method==="POST"&&publishMatch){
  #|       const decodedApplication=decodePathSegment(publishMatch[1]),decodedEventType=decodePathSegment(publishMatch[2]);
  #|       if(!decodedApplication.ok||!decodedEventType.ok)return json(res,400,{error:"invalid_path_encoding"});
  #|       const payload=await bodyOf(req,res);if(payload===null)return;
  #|       const contentType=String(req.headers["content-type"]||"").toLowerCase();
  #|       const mediaType=contentType.split(";",1)[0].trim();
  #|       if(mediaType!=="application/json")return json(res,415,{error:"unsupported_media_type"});
  #|       try{JSON.parse(payload);}catch(_){return json(res,422,{error:"invalid_json"});}
  #|       const applicationId=decodedApplication.value,eventType=decodedEventType.value,idempotencyKey=String(req.headers["idempotency-key"]||"").trim();
  #|       if(!idempotencyKey)return json(res,400,{error:"missing_idempotency_key"});
  #|       let plan;try{plan=JSON.parse(publisher(applicationId,String(req.headers.authorization||""),idempotencyKey,eventType,payload));}catch(error){return json(res,500,{error:"publisher_failed"});}
  #|       if(!plan.accepted)return json(res,Number(plan.status||422),{error:plan.code||"publication_rejected"});
  #|       const existing=db.prepare("SELECT id,fingerprint FROM events WHERE source='outbound' AND application_id=? AND idempotency_key=?").get(applicationId,idempotencyKey);
  #|       if(existing){if(existing.fingerprint!==plan.fingerprint)return json(res,409,{error:"idempotency_conflict",eventId:existing.id});return json(res,200,{accepted:true,duplicate:true,eventId:existing.id,deliveries:0});}
  #|       const createdAt=now();
  #|       try{transaction(()=>{const targets=plan.deliveries.map(item=>item.target);insertEvent.run(plan.event_id,"outbound",plan.application_id,"hooklab",plan.event_type,null,plan.idempotency_key,plan.fingerprint,payload,plan.redacted_body,JSON.stringify(safeHeaders(req.headers)),createdAt,JSON.stringify(targets),JSON.stringify(plan.deliveries));addDeliveries(plan.event_id,plan.deliveries,createdAt);});}
  #|       catch(error){const raced=db.prepare("SELECT id,fingerprint FROM events WHERE source='outbound' AND application_id=? AND idempotency_key=?").get(applicationId,idempotencyKey);if(raced&&raced.fingerprint===plan.fingerprint)return json(res,200,{accepted:true,duplicate:true,eventId:raced.id,deliveries:0});if(raced)return json(res,409,{error:"idempotency_conflict",eventId:raced.id});return json(res,500,{error:"storage_commit_failed"});}
  #|       return json(res,202,{accepted:true,duplicate:false,eventId:plan.event_id,deliveries:plan.deliveries.length});
  #|     }
  #|     const hookMatch=url.pathname.match(/^\/hooks\/([^/]+)$/);
  #|     if(req.method==="POST"&&hookMatch){
  #|       const decodedProvider=decodePathSegment(hookMatch[1]);if(!decodedProvider.ok)return json(res,400,{error:"invalid_path_encoding"});
  #|       const body=await bodyOf(req,res);if(body===null)return;
  #|       let accepted;try{accepted=JSON.parse(handler(decodedProvider.value,handlerHeaders(req.headers),body,BigInt(Math.floor(now()/1000))));}catch(error){return json(res,500,{error:"gateway_handler_failed"});}
  #|       if(!accepted.accepted){const status=accepted.code==="replay_detected"?200:accepted.code==="invalid_payload"?422:401;return json(res,status,accepted);}
  #|       const previous=eventRow(accepted.event_id);if(previous)return json(res,200,{accepted:true,duplicate:true,eventId:previous.id});
  #|       const outputs=accepted.deliveries.map(item=>({target:item.target,payload:typeof item.payload==="string"?item.payload:null})),targets=outputs.map(item=>item.target),createdAt=now();
  #|       try{transaction(()=>{insertEvent.run(accepted.event_id,"ingress",null,accepted.provider,accepted.event_type,accepted.delivery_id||null,null,null,body,accepted.redacted_body,JSON.stringify(safeHeaders(req.headers)),createdAt,JSON.stringify(targets),JSON.stringify(outputs));addDeliveries(accepted.event_id,accepted.deliveries,createdAt);});}
  #|       catch(error){const raced=eventRow(accepted.event_id);if(raced)return json(res,200,{accepted:true,duplicate:true,eventId:raced.id});return json(res,500,{error:"storage_commit_failed"});}
  #|       return json(res,202,{accepted:true,duplicate:false,eventId:accepted.event_id,deliveries:accepted.deliveries.length});
  #|     }
  #|     json(res,404,{error:"not_found"});
  #|   };
  #|   const server=http.createServer((req,res)=>{void handleRequest(req,res).catch(error=>{console.error("HookLab request failed",error);if(!res.headersSent)return json(res,500,{error:"internal_error"});res.destroy();});});
  #|   server.requestTimeout=20000;server.headersTimeout=10000;server.listen(port,"127.0.0.1");
  #|   const shutdown=signal=>{clearInterval(pumpTimer);server.close(()=>{try{db.exec("PRAGMA wal_checkpoint(TRUNCATE)");}catch(_){}db.close();console.log("HookLab Gateway stopped by "+signal);});};
  #|   process.once("SIGINT",()=>shutdown("SIGINT"));process.once("SIGTERM",()=>shutdown("SIGTERM"));
  #| }
