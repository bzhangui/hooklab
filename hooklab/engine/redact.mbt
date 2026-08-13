///|
pub(all) struct RedactionPolicy {
  fields : Array[String]
  replacement : String
} derive(Eq, Debug)

///|
pub fn RedactionPolicy::secure_default() -> RedactionPolicy {
  {
    fields: [
      "authorization", "cookie", "set-cookie", "token", "access_token", "refresh_token",
      "secret", "password", "email", "phone",
    ],
    replacement: "[REDACTED]",
  }
}

///|
fn RedactionPolicy::contains(self : RedactionPolicy, key : String) -> Bool {
  let lowered = @core.ascii_lower(key)
  self.fields.any(fn(field) { @core.ascii_lower(field) == lowered })
}

///|
/// Redacts matching JSON object keys at every nesting depth. Invalid JSON is
/// returned unchanged so diagnostics never destroy the original evidence.
pub fn redact_json(
  body : String,
  policy? : RedactionPolicy = RedactionPolicy::secure_default(),
) -> String {
  try @json.parse(body) catch {
    _ => body
  } noraise {
    parsed => {
      let replacer = @json.Replacer::Replacer(fn(key, value) {
        if policy.contains(key) {
          Some(Json::string(policy.replacement))
        } else {
          Some(value)
        }
      })
      parsed.transform(replacer).stringify(indent=2)
    }
  }
}

///|
pub fn redact_headers(
  headers : Array[@core.Header],
  policy? : RedactionPolicy = RedactionPolicy::secure_default(),
) -> Array[@core.Header] {
  headers.map(fn(item) {
    if policy.contains(item.name) {
      @core.header(item.name, policy.replacement)
    } else {
      item
    }
  })
}
