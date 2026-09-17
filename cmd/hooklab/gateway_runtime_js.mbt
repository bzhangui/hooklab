///|
extern "js" fn run_gateway_runtime(
  port : Int,
  data_dir : String,
  handler : (String, String, String, Int64) -> String,
  decision : (Int, Int, String, String) -> String,
  dashboard : String,
) -> Unit =
  #| function(port, dataDir, handler, decision, dashboard) {
  #|   const http = require("node:http");
  #|   const fs = require("node:fs");
  #|   const path = require("node:path");
  #|   const crypto = require("node:crypto");
  #|   const root = path.resolve(dataDir);
  #|   const statePath = path.join(root, "state.json");
  #|   fs.mkdirSync(root, {recursive: true});
  #|   const emptyState = () => ({version: 1, events: [], deliveries: []});
  #|   let state = emptyState();
  #|   try {
  #|     if (fs.existsSync(statePath)) {
  #|       const loaded = JSON.parse(fs.readFileSync(statePath, "utf8"));
  #|       if (loaded && loaded.version === 1 && Array.isArray(loaded.events) && Array.isArray(loaded.deliveries)) state = loaded;
  #|     }
  #|   } catch (error) {
  #|     const backup = statePath + ".corrupt-" + Date.now();
  #|     try { fs.renameSync(statePath, backup); } catch (_) {}
  #|     console.error(JSON.stringify({warning: "state_recovery_failed", backup, error: String(error)}));
  #|   }
  #|   for (const item of state.deliveries) {
  #|     if (item.state === "in_flight") {
  #|       item.state = "scheduled";
  #|       item.nextAttemptAt = Date.now();
  #|       item.lastError = "recovered after process restart";
  #|     }
  #|   }
  #|   function save() {
  #|     const temp = statePath + ".tmp-" + process.pid;
  #|     fs.writeFileSync(temp, JSON.stringify(state, null, 2), {encoding: "utf8", mode: 0o600});
  #|     fs.renameSync(temp, statePath);
  #|   }
  #|   save();
  #|   const hash = value => crypto.createHash("sha256").update(value).digest("hex").slice(0, 24);
  #|   const json = (res, status, value) => {
  #|     const body = JSON.stringify(value);
  #|     res.writeHead(status, {"content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(body), "cache-control": "no-store"});
  #|     res.end(body);
  #|   };
  #|   const publicEvent = event => ({id: event.id, provider: event.provider, eventType: event.eventType, deliveryId: event.deliveryId, redactedBody: event.redactedBody, receivedAt: event.receivedAt, targets: event.targets});
  #|   const publicDelivery = item => ({id: item.id, eventId: item.eventId, target: item.target, state: item.state, attempt: item.attempt, nextAttemptAt: item.nextAttemptAt, lastStatus: item.lastStatus, lastError: item.lastError, updatedAt: item.updatedAt});
  #|   const stats = () => {
  #|     const result = {events: state.events.length, pending: 0, scheduled: 0, in_flight: 0, delivered: 0, dead_lettered: 0};
  #|     for (const item of state.deliveries) if (Object.hasOwn(result, item.state)) result[item.state]++;
  #|     return result;
  #|   };
  #|   const safeHeaders = headers => Object.entries(headers).map(([name, value]) => {
  #|     const lower = name.toLowerCase();
  #|     const sensitive = lower === "authorization" || lower === "cookie" || lower === "set-cookie" || lower === "x-api-key" || lower.includes("signature");
  #|     return {name, value: sensitive ? "[REDACTED]" : String(Array.isArray(value) ? value.join(",") : value ?? "")};
  #|   });
  #|   const handlerHeaders = headers => JSON.stringify(Object.entries(headers).map(([name, value]) => ({name, value: String(Array.isArray(value) ? value.join(",") : value ?? "")})));
  #|   const bodyOf = (req, res) => new Promise(resolve => {
  #|     const chunks = [];
  #|     let size = 0;
  #|     let tooLarge = false;
  #|     req.on("data", chunk => {
  #|       size += chunk.length;
  #|       if (size > 1024 * 1024) tooLarge = true;
  #|       else chunks.push(chunk);
  #|     });
  #|     req.on("end", () => {
  #|       if (tooLarge) {
  #|         json(res, 413, {error: "payload_too_large", maxBytes: 1048576});
  #|         resolve(null);
  #|       } else resolve(Buffer.concat(chunks).toString("utf8"));
  #|     });
  #|     req.on("error", () => resolve(null));
  #|   });
  #|   function enqueueReplay(event, existing) {
  #|     const now = Date.now();
  #|     const sequence = state.deliveries.length + 1;
  #|     const outputs = Array.isArray(event.outputs) ? event.outputs : event.targets.map(target => ({target, payload: null}));
  #|     for (const output of outputs) {
  #|       state.deliveries.push({id: "delivery:" + hash(event.id + "\n" + output.target + "\n" + now + "\n" + sequence), eventId: event.id, target: output.target, payload: typeof output.payload === "string" ? output.payload : null, state: "pending", attempt: 0, nextAttemptAt: now, lastStatus: null, lastError: existing ? "manual replay" : null, createdAt: now, updatedAt: now});
  #|     }
  #|   }
  #|   let pumping = false;
  #|   async function pump() {
  #|     if (pumping) return;
  #|     const now = Date.now();
  #|     const item = state.deliveries.find(x => (x.state === "pending" || x.state === "scheduled") && x.nextAttemptAt <= now);
  #|     if (!item) return;
  #|     pumping = true;
  #|     item.state = "in_flight";
  #|     item.attempt++;
  #|     item.updatedAt = now;
  #|     save();
  #|     const event = state.events.find(x => x.id === item.eventId);
  #|     let status = 0;
  #|     let retryAfter = "";
  #|     let transportError = "";
  #|     try {
  #|       if (!event) throw new Error("event payload is missing");
  #|       const payload = typeof item.payload === "string" ? item.payload : event.body;
  #|       const response = await fetch(item.target, {method: "POST", headers: {"content-type": "application/json", "x-hooklab-event-id": event.id, "x-hooklab-delivery-id": item.id, "x-hooklab-event-type": event.eventType}, body: payload, signal: AbortSignal.timeout(15000)});
  #|       status = response.status;
  #|       retryAfter = response.headers.get("retry-after") || "";
  #|       await response.arrayBuffer();
  #|     } catch (error) {
  #|       transportError = String(error);
  #|     }
  #|     let result;
  #|     try { result = JSON.parse(decision(item.attempt, status, retryAfter, transportError)); }
  #|     catch (error) { result = {decision: "dead_letter", delay_ms: 0, reason: "invalid MoonBit delivery decision: " + String(error)}; }
  #|     item.lastStatus = status || null;
  #|     item.updatedAt = Date.now();
  #|     if (result.decision === "success") {
  #|       item.state = "delivered";
  #|       item.lastError = null;
  #|     } else if (result.decision === "retry") {
  #|       item.state = "scheduled";
  #|       item.nextAttemptAt = Date.now() + Number(result.delay_ms || 0);
  #|       item.lastError = transportError || ("HTTP " + status);
  #|     } else {
  #|       item.state = "dead_lettered";
  #|       item.lastError = result.reason || transportError || ("HTTP " + status);
  #|     }
  #|     save();
  #|     pumping = false;
  #|   }
  #|   setInterval(() => pump().catch(error => { pumping = false; console.error(error); }), 250);
  #|   const server = http.createServer(async (req, res) => {
  #|     const url = new URL(req.url || "/", "http://127.0.0.1");
  #|     if (req.method === "GET" && url.pathname === "/") {
  #|       res.writeHead(200, {"content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff"});
  #|       return res.end(dashboard);
  #|     }
  #|     if (req.method === "GET" && url.pathname === "/health") return json(res, 200, {status: "ok", ...stats()});
  #|     if (req.method === "GET" && url.pathname === "/api/stats") return json(res, 200, stats());
  #|     if (req.method === "GET" && url.pathname === "/api/events") return json(res, 200, state.events.map(publicEvent));
  #|     if (req.method === "GET" && url.pathname === "/api/deliveries") return json(res, 200, state.deliveries.map(publicDelivery));
  #|     const retryMatch = url.pathname.match(/^\/api\/deliveries\/([^/]+)\/retry$/);
  #|     if (req.method === "POST" && retryMatch) {
  #|       const item = state.deliveries.find(x => x.id === decodeURIComponent(retryMatch[1]));
  #|       if (!item) return json(res, 404, {error: "delivery_not_found"});
  #|       if (item.state !== "dead_lettered") return json(res, 409, {error: "invalid_transition", state: item.state});
  #|       item.state = "pending"; item.attempt = 0; item.nextAttemptAt = Date.now(); item.lastStatus = null; item.lastError = "manual retry"; item.updatedAt = Date.now(); save();
  #|       return json(res, 202, publicDelivery(item));
  #|     }
  #|     const replayMatch = url.pathname.match(/^\/api\/events\/([^/]+)\/replay$/);
  #|     if (req.method === "POST" && replayMatch) {
  #|       const event = state.events.find(x => x.id === decodeURIComponent(replayMatch[1]));
  #|       if (!event) return json(res, 404, {error: "event_not_found"});
  #|       enqueueReplay(event, true); save();
  #|       return json(res, 202, {eventId: event.id, replayed: event.targets.length});
  #|     }
  #|     const hookMatch = url.pathname.match(/^\/hooks\/([^/]+)$/);
  #|     if (req.method === "POST" && hookMatch) {
  #|       const body = await bodyOf(req, res);
  #|       if (body === null) return;
  #|       let accepted;
  #|       try { accepted = JSON.parse(handler(decodeURIComponent(hookMatch[1]), handlerHeaders(req.headers), body, BigInt(Math.floor(Date.now() / 1000)))); }
  #|       catch (error) { return json(res, 500, {error: "gateway_handler_failed", message: String(error)}); }
  #|       if (!accepted.accepted) {
  #|         const status = accepted.code === "replay_detected" ? 200 : accepted.code === "invalid_payload" ? 422 : 401;
  #|         return json(res, status, accepted);
  #|       }
  #|       const previous = state.events.find(x => x.id === accepted.event_id);
  #|       if (previous) return json(res, 200, {accepted: true, duplicate: true, eventId: previous.id});
  #|       const outputs = accepted.deliveries.map(x => ({target: x.target, payload: typeof x.payload === "string" ? x.payload : null}));
  #|       const targets = outputs.map(x => x.target);
  #|       const event = {id: accepted.event_id, provider: accepted.provider, eventType: accepted.event_type, deliveryId: accepted.delivery_id, body, redactedBody: accepted.redacted_body, headers: safeHeaders(req.headers), receivedAt: Date.now(), targets, outputs};
  #|       state.events.push(event);
  #|       for (const work of accepted.deliveries) state.deliveries.push({id: work.id, eventId: event.id, target: work.target, payload: typeof work.payload === "string" ? work.payload : null, state: "pending", attempt: 0, nextAttemptAt: Date.now(), lastStatus: null, lastError: null, createdAt: Date.now(), updatedAt: Date.now()});
  #|       save();
  #|       return json(res, 202, {accepted: true, duplicate: false, eventId: event.id, deliveries: accepted.deliveries.length});
  #|     }
  #|     json(res, 404, {error: "not_found"});
  #|   });
  #|   server.requestTimeout = 20000;
  #|   server.headersTimeout = 10000;
  #|   server.listen(port, "127.0.0.1");
  #|   const shutdown = signal => server.close(() => { save(); console.log("HookLab Gateway stopped by " + signal); });
  #|   process.once("SIGINT", () => shutdown("SIGINT"));
  #|   process.once("SIGTERM", () => shutdown("SIGTERM"));
  #| }
