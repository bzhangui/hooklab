///|
fn json_escape(value : String) -> String {
  let out = StringBuilder::new()
  for c in value {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      value if value.to_int() < 32 => {
        let number = value.to_int()
        let digits = "0123456789abcdef"
        out.write_string("\\u00")
        out.write_char(digits[number / 16].to_int().unsafe_to_char())
        out.write_char(digits[number % 16].to_int().unsafe_to_char())
      }
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn json_string(value : String) -> String {
  "\"" + json_escape(value) + "\""
}

///|
fn html_escape(value : String) -> String {
  let out = StringBuilder::new()
  for c in value {
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn routes_json(routes : Array[@engine.RouteMatch]) -> String {
  let parts : Array[String] = []
  for item in routes {
    parts.push(
      "{\"rule\":" +
      json_string(item.rule_name) +
      ",\"target\":" +
      json_string(item.target) +
      "}",
    )
  }
  "[" + parts.join(",") + "]"
}

///|
/// Stable, dependency-free JSON suitable for CI and shell integrations.
pub fn result_json(result : @pipeline.ProcessingResult) -> String {
  match result {
    @pipeline.Rejected(failure) =>
      "{\"status\":\"rejected\",\"code\":" +
      json_string(@core.failure_code_name(failure.code)) +
      ",\"stage\":" +
      json_string(@core.stage_name(failure.stage)) +
      ",\"message\":" +
      json_string(failure.message) +
      ",\"suggestion\":" +
      json_string(failure.suggestion) +
      "}"
    @pipeline.Processed(output) =>
      "{\"status\":\"processed\",\"provider\":" +
      json_string(@core.provider_name(output.event.provider)) +
      ",\"event_type\":" +
      json_string(output.event.event_type) +
      ",\"routes\":" +
      routes_json(output.routes) +
      ",\"redacted_body\":" +
      json_string(output.redacted_body) +
      "}"
  }
}

///|
/// Creates a single-file offline diagnosis page. It contains no remote assets,
/// executable scripts, secrets, or unredacted diagnostic payloads.
pub fn result_html(result : @pipeline.ProcessingResult) -> String {
  let (status, summary, detail, suggestion) = match result {
    @pipeline.Rejected(failure) =>
      (
        "Rejected",
        @core.failure_code_name(failure.code) +
        " at " +
        @core.stage_name(failure.stage),
        failure.message,
        failure.suggestion,
      )
    @pipeline.Processed(output) =>
      (
        "Processed",
        @core.provider_name(output.event.provider) +
        " / " +
        output.event.event_type,
        output.redacted_body,
        "Matched routes: " + output.routes.length().to_string(),
      )
  }
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" +
  "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
  "<title>HookLab diagnosis</title><style>" +
  "body{font:16px system-ui;max-width:920px;margin:3rem auto;padding:0 1rem;color:#172033;background:#f4f7fb}" +
  "main{background:white;border-radius:16px;padding:2rem;box-shadow:0 8px 30px #16325c18}" +
  "h1{margin-top:0}.status{font-weight:700;color:#2457d6}pre{white-space:pre-wrap;word-break:break-word;background:#101827;color:#dce8ff;padding:1rem;border-radius:8px}" +
  "</style></head><body><main><h1>HookLab diagnosis</h1><p class=\"status\">" +
  html_escape(status) +
  "</p><h2>Summary</h2><p>" +
  html_escape(summary) +
  "</p><h2>Evidence (redacted)</h2><pre>" +
  html_escape(detail) +
  "</pre><h2>Next action</h2><p>" +
  html_escape(suggestion) +
  "</p></main></body></html>"
}
