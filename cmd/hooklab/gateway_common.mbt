///|
fn gateway_hex_digit(value : Int) -> Char {
  if value < 10 {
    ('0'.to_int() + value).unsafe_to_char()
  } else {
    ('a'.to_int() + value - 10).unsafe_to_char()
  }
}

///|
fn gateway_json_escape(value : String) -> String {
  let out = StringBuilder()
  for c in value {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => {
        let code = c.to_int()
        if code < 0x20 {
          out.write_string("\\u00")
          out.write_char(gateway_hex_digit(code / 16))
          out.write_char(gateway_hex_digit(code % 16))
        } else {
          out.write_char(c)
        }
      }
    }
  }
  out.to_string()
}

///|
fn gateway_json_string(value : String) -> String {
  "\"" + gateway_json_escape(value) + "\""
}

///|
fn headers_from_json(value : String) -> Array[@core.Header] {
  try @json.parse(value) catch {
    _ => []
  } noraise {
    parsed =>
      match parsed {
        Array(items) => {
          let headers : Array[@core.Header] = []
          for item in items {
            match item {
              Object(fields) => {
                let name = match fields.get_from_string("name") {
                  Some(String(text)) => text
                  _ => ""
                }
                let value = match fields.get_from_string("value") {
                  Some(String(text)) => text
                  _ => ""
                }
                if !name.is_empty() {
                  headers.push(@core.header(name, value))
                }
              }
              _ => ()
            }
          }
          headers
        }
        _ => []
      }
  }
}

///|
fn gateway_accept_json(
  gateway : @gateway.Gateway,
  configured_provider : @core.Provider,
  secrets : Array[String],
  provider_name : String,
  headers_json : String,
  body : String,
  received_at : Int64,
) -> String {
  guard provider_from_string(provider_name) is Some(provider) else {
    return "{\"accepted\":false,\"code\":\"unsupported_provider\",\"message\":\"Unknown provider path.\"}"
  }
  if provider != configured_provider {
    return "{\"accepted\":false,\"code\":\"provider_mismatch\",\"message\":\"This gateway endpoint is not configured for that provider.\"}"
  }
  let request : @core.WebhookRequest = {
    provider,
    headers: headers_from_json(headers_json),
    body,
    received_at,
  }
  match
    gateway.prepare(request, secrets, received_at * 1000L, verification_policy={
      tolerance_seconds: 300L,
      reject_future_seconds: 30L,
      require_delivery_id: true,
    }) {
    @gateway.PreparationRejected(failure) =>
      "{\"accepted\":false,\"code\":" +
      gateway_json_string(@core.failure_code_name(failure.code)) +
      ",\"stage\":" +
      gateway_json_string(@core.stage_name(failure.stage)) +
      ",\"message\":" +
      gateway_json_string(failure.message) +
      "}"
    @gateway.Prepared(event, deliveries) => {
      let work : Array[String] = []
      for delivery in deliveries {
        work.push(
          "{\"id\":" +
          gateway_json_string(delivery.id) +
          ",\"target\":" +
          gateway_json_string(delivery.target) +
          ",\"payload\":" +
          (match delivery.payload {
            Some(value) => gateway_json_string(value)
            None => "null"
          }) +
          "}",
        )
      }
      "{\"accepted\":true,\"event_id\":" +
      gateway_json_string(event.id) +
      ",\"provider\":" +
      gateway_json_string(@core.provider_name(event.provider)) +
      ",\"event_type\":" +
      gateway_json_string(event.event_type) +
      ",\"delivery_id\":" +
      gateway_json_string(event.delivery_id.unwrap_or("")) +
      ",\"redacted_body\":" +
      gateway_json_string(event.redacted_body) +
      ",\"deliveries\":[" +
      work.join(",") +
      "]}"
    }
  }
}

///|
fn gateway_decision_json(
  attempt : Int,
  status : Int,
  retry_after : String,
  transport_error : String,
) -> String {
  let outcome : @engine.AttemptOutcome = if !transport_error.is_empty() {
    @engine.TransportFailure(transport_error)
  } else if status >= 200 && status < 300 {
    @engine.Delivered(status)
  } else if status == 408 || status == 425 || status == 429 || status >= 500 {
    @engine.Retryable(status, "retryable HTTP response")
  } else {
    @engine.Permanent(status, "non-retryable HTTP response")
  }
  match
    @engine.decide_delivery_with_retry_after(
      @engine.RetryPolicy::default(),
      attempt,
      outcome,
      if retry_after.is_empty() {
        None
      } else {
        Some(retry_after)
      },
    ) {
    @engine.Success => "{\"decision\":\"success\",\"delay_ms\":0}"
    @engine.RetryAfter(delay) =>
      "{\"decision\":\"retry\",\"delay_ms\":" + delay.to_string() + "}"
    @engine.DeadLetter(reason) =>
      "{\"decision\":\"dead_letter\",\"delay_ms\":0,\"reason\":" +
      gateway_json_string(reason) +
      "}"
  }
}

///|
fn gateway_dashboard_html() -> String {
  (
    #|<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HookLab Gateway</title>
    #|<style>:root{color-scheme:light dark;font-family:Inter,system-ui,sans-serif}body{margin:0;background:#0b1020;color:#e9efff}main{max-width:1100px;margin:auto;padding:32px 20px}.hero{display:flex;justify-content:space-between;align-items:end;gap:20px}.badge{color:#8fb2ff}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:24px 0}.card,table{background:#141c31;border:1px solid #293653;border-radius:14px}.card{padding:18px}.value{font-size:28px;font-weight:750}table{width:100%;border-collapse:collapse;overflow:hidden}th,td{text-align:left;padding:12px;border-bottom:1px solid #293653;font-size:14px}th{color:#9eb0d2}.ok{color:#7ee2a8}.bad{color:#ff9b9b}button{border:0;border-radius:9px;background:#5c83ff;color:white;padding:9px 13px;cursor:pointer}code{color:#b9ccff}</style></head><body><main>
    #|<div class="hero"><div><div class="badge">MoonBit-native event delivery</div><h1>HookLab Gateway</h1><p>安全接收、持久化、可靠投递、死信与回放。</p></div><button id="refresh">刷新</button></div>
    #|<section class="grid" id="stats"></section><h2>最近投递</h2><table><thead><tr><th>状态</th><th>熔断</th><th>事件</th><th>目标</th><th>尝试</th><th>操作</th></tr></thead><tbody id="deliveries"></tbody></table>
    #|<h2>投递耗时</h2><section class="grid" id="metrics"></section>
    #|<h2>最近事件</h2><table><thead><tr><th>时间</th><th>提供方</th><th>类型</th><th>事件 ID</th></tr></thead><tbody id="events"></tbody></table>
    #|</main><script>
    #|const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));
    #|async function retry(id){await fetch("/api/deliveries/"+encodeURIComponent(id)+"/retry",{method:"POST"});await load()}
    #|async function load(){const [s,e,d,m]=await Promise.all(["/api/stats","/api/events","/api/deliveries","/api/metrics"].map(x=>fetch(x).then(r=>r.json())));
    #|document.querySelector("#stats").innerHTML=Object.entries(s).map(([k,v])=>'<div class="card"><div>'+esc(k)+'</div><div class="value">'+esc(v)+'</div></div>').join("");
    #|document.querySelector("#metrics").innerHTML=m.targets.map(x=>'<div class="card"><div>'+esc(x.id)+' · 已完成尝试</div><div class="value">'+esc(x.total)+'</div><small>'+Object.entries(x.buckets).map(([k,v])=>esc(k)+': '+esc(v)).join(' · ')+'</small></div>').join("");
    #|document.querySelector("#events").innerHTML=e.slice().reverse().slice(0,50).map(x=>'<tr><td>'+esc(new Date(x.receivedAt).toLocaleString())+'</td><td>'+esc(x.provider)+'</td><td>'+esc(x.eventType)+'</td><td><code>'+esc(x.id)+'</code></td></tr>').join("");
    #|document.querySelector("#deliveries").innerHTML=d.slice().reverse().slice(0,50).map(x=>'<tr><td class="'+(x.state==="delivered"?"ok":x.state==="dead_lettered"?"bad":"")+'">'+esc(x.state)+'</td><td>'+esc(x.circuitState)+'</td><td><code>'+esc(x.eventId)+'</code></td><td>'+esc(x.target)+'</td><td>'+esc(x.attempt)+'</td><td>'+(x.state==="dead_lettered"?'<button onclick="retry(\''+esc(x.id)+'\')">重试</button>':"")+'</td></tr>').join("")}
    #|document.querySelector("#refresh").onclick=load;load();setInterval(load,3000);
    #|</script></body></html>
  )
}

///|
fn serve_gateway(args : Array[String]) -> Unit {
  guard args.length() >= 4 else {
    usage()
    set_exit_code(1)
    return
  }
  guard provider_from_string(args[1]) is Some(provider) else {
    println("Unknown provider: " + args[1])
    set_exit_code(1)
    return
  }
  let secret_input = if args[2] == "-" {
    read_environment("HOOKLAB_SECRET").unwrap_or("") +
    "," +
    read_environment("HOOKLAB_PREVIOUS_SECRETS").unwrap_or("")
  } else {
    args[2]
  }
  let secrets : Array[String] = []
  for item in secret_input.split(",") {
    let secret = @core.trim_ascii(item.to_owned())
    if !secret.is_empty() {
      secrets.push(secret)
    }
  }
  guard !secrets.is_empty() else {
    println("At least one non-empty secret is required.")
    set_exit_code(1)
    return
  }
  let routes : Array[@engine.RouteRule] = []
  let mut target_index = 1
  for item in args[3].split(",") {
    let target = @core.trim_ascii(item.to_owned())
    if target.has_prefix("http://") || target.has_prefix("https://") {
      routes.push({
        name: "target-" + target_index.to_string(),
        path: "$",
        operator: @engine.Exists,
        expected: "",
        target,
      })
      target_index = target_index + 1
    }
  }
  guard !routes.is_empty() else {
    println("At least one HTTP(S) delivery target is required.")
    set_exit_code(1)
    return
  }
  let port = if args.length() > 4 {
    try @string.parse_int(args[4]) catch {
      _ => 8787
    } noraise {
      value => value
    }
  } else {
    8787
  }
  let data_dir = if args.length() > 5 { args[5] } else { ".hooklab-data" }
  let gateway = @gateway.Gateway::new(routes)
  println("HookLab Gateway listening on http://127.0.0.1:" + port.to_string())
  println(
    "Webhook endpoint: http://127.0.0.1:" +
    port.to_string() +
    "/hooks/" +
    @core.provider_name(provider),
  )
  let limiter = @delivery.DispatchLimiter::new([])
  let breaker = @delivery.CircuitBreaker::new([])
  let latency = @delivery.LatencyMetrics::new()
  run_gateway_runtime(
    port,
    data_dir,
    fn(provider_name, headers_json, body, received_at) {
      gateway_accept_json(
        gateway, provider, secrets, provider_name, headers_json, body, received_at,
      )
    },
    fn(_, _, _, _, _) {
      "{\"accepted\":false,\"status\":404,\"code\":\"outbound_disabled\"}"
    },
    fn(_, _, _, _, _, _, _, _) { "" },
    gateway_decision_json,
    fn(target, now_ms) {
      if !breaker.try_acquire(target, now_ms) {
        false
      } else if limiter.try_acquire(target, now_ms) {
        true
      } else {
        breaker.cancel(target)
        false
      }
    },
    fn(target) {
      breaker.cancel(target)
      limiter.release(target)
    },
    fn(target, result, now_ms, duration_ms) {
      let outcome = if result == 1 {
        @delivery.Success
      } else if result == 2 {
        @delivery.RetryableFailure
      } else {
        @delivery.Neutral
      }
      breaker.complete(target, outcome, now_ms)
      limiter.release(target)
      latency.record(target, duration_ms)
    },
    fn(target, now_ms) { breaker.state(target, now_ms) },
    fn() { latency.to_json() },
    "{\"applications\":[],\"endpoints\":[],\"subscriptions\":[]}",
    gateway_dashboard_html(),
  )
}
