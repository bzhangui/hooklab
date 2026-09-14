///|
pub(all) struct WebhookContract {
  name : String
  provider : @core.Provider
  event_type : String?
  required_headers : Array[String]
  required_paths : Array[String]
  max_body_chars : Int
} derive(Eq, Debug)

///|
pub(all) struct ContractIssue {
  code : String
  location : String
  message : String
} derive(Eq, Debug)

///|
pub(all) enum ContractResult {
  Valid
  Invalid(Array[ContractIssue])
} derive(Eq, Debug)

///|
fn parse_array_index(value : String) -> Int? {
  if value.is_empty() {
    return None
  }
  let mut index = 0
  for c in value {
    if c < '0' || c > '9' {
      return None
    }
    index = index * 10 + c.to_int() - '0'.to_int()
  }
  Some(index)
}

///|
fn json_path_exists(root : Json, path : String) -> Bool {
  let normalized = if path.has_prefix("$.") {
    path[2:].to_owned()
  } else {
    path
  }
  if normalized.is_empty() || normalized == "$" {
    return true
  }
  let mut current = root
  for segment in normalized.split(".") {
    let key = segment.to_owned()
    match current {
      Object(values) =>
        match values.get_from_string(key) {
          Some(next) => current = next
          None => return false
        }
      Array(values) =>
        match parse_array_index(key) {
          Some(index) if index < values.length() => current = values[index]
          _ => return false
        }
      _ => return false
    }
  }
  true
}

///|
/// Validates the transport-independent contract after signature verification.
/// Every issue is returned so CI users can fix a payload in one iteration.
pub fn validate(
  request : @core.WebhookRequest,
  event_type : String,
  contract : WebhookContract,
) -> ContractResult {
  let issues : Array[ContractIssue] = []
  if request.provider != contract.provider {
    issues.push({
      code: "provider_mismatch",
      location: "provider",
      message: "The request provider does not match this contract.",
    })
  }
  match contract.event_type {
    Some(expected) if expected != event_type =>
      issues.push({
        code: "event_type_mismatch",
        location: "event_type",
        message: "Expected event type " +
        expected +
        ", received " +
        event_type +
        ".",
      })
    _ => ()
  }
  if contract.max_body_chars > 0 &&
    request.body.length() > contract.max_body_chars {
    issues.push({
      code: "body_too_large",
      location: "body",
      message: "The request body exceeds the contract size limit.",
    })
  }
  for name in contract.required_headers {
    if @core.find_header(request.headers, name) is None {
      issues.push({
        code: "missing_header",
        location: "headers." + @core.ascii_lower(name),
        message: "Required header " + name + " is missing.",
      })
    }
  }
  try @json.parse(request.body) catch {
    _ =>
      issues.push({
        code: "invalid_json",
        location: "body",
        message: "The request body is not valid JSON.",
      })
  } noraise {
    parsed =>
      for path in contract.required_paths {
        if !json_path_exists(parsed, path) {
          issues.push({
            code: "missing_path",
            location: path,
            message: "Required JSON path " + path + " is missing.",
          })
        }
      }
  }
  if issues.is_empty() {
    Valid
  } else {
    Invalid(issues)
  }
}
