///|
fn event_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get_from_string(key)
    _ => None
  }
}

///|
fn event_text(value : Json, key : String) -> String? {
  match event_field(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn event_issue(
  issues : Array[ContractIssue],
  code : String,
  location : String,
) -> Unit {
  if issues.length() < 50 {
    issues.push({ code, location, message: code, })
  }
}

///|
fn schema_type_matches(value : Json, expected : String) -> Bool {
  match value {
    Object(_) => expected == "object"
    Array(_) => expected == "array"
    String(_) => expected == "string"
    Number(number, ..) =>
      expected == "number" ||
      (expected == "integer" && number == number.trunc())
    True | False => expected == "boolean"
    Null => expected == "null"
  }
}

///|
fn validate_schema_value(
  schema : Json,
  value : Json,
  location : String,
  depth : Int,
  issues : Array[ContractIssue],
) -> Unit {
  if issues.length() >= 50 {
    return
  }
  if depth > 16 {
    event_issue(issues, "max_depth", location)
    return
  }
  match event_text(schema, "type") {
    Some(expected) if !schema_type_matches(value, expected) =>
      event_issue(issues, "type", location)
    _ => ()
  }
  match event_field(schema, "enum") {
    Some(Array(candidates)) => {
      let mut matched = false
      for candidate in candidates {
        if candidate == value {
          matched = true
          break
        }
      }
      if !matched {
        event_issue(issues, "enum", location)
      }
    }
    _ => ()
  }
  match value {
    Object(fields) => {
      match event_field(schema, "required") {
        Some(Array(required)) =>
          for item in required {
            if item is String(name) && fields.get_from_string(name) is None {
              event_issue(issues, "required", location + "." + name)
            }
          }
        _ => ()
      }
      let definitions = event_field(schema, "properties")
      let reject_extras = match event_field(schema, "additionalProperties") {
        Some(False) => true
        _ => false
      }
      for key, child in fields {
        match definitions {
          Some(Object(properties)) =>
            match properties.get_from_string(key) {
              Some(child_schema) =>
                validate_schema_value(
                  child_schema,
                  child,
                  location + "." + key,
                  depth + 1,
                  issues,
                )
              None =>
                if reject_extras {
                  event_issue(
                    issues,
                    "additional_property",
                    location + "." + key,
                  )
                }
            }
          _ =>
            if reject_extras {
              event_issue(issues, "additional_property", location + "." + key)
            }
        }
      }
    }
    Array(items) =>
      match event_field(schema, "items") {
        Some(item_schema) =>
          for index, child in items {
            validate_schema_value(
              item_schema,
              child,
              location + "[" + index.to_string() + "]",
              depth + 1,
              issues,
            )
          }
        _ => ()
      }
    _ => ()
  }
}

///|
/// Bounded structured CloudEvents and JSON Schema subset validation for the
/// PostgreSQL adapter. The adapter separately enforces content type, URL and
/// schema-definition policy before this pure MoonBit check runs.
pub fn validate_event_json(
  payload : String,
  media_type : String,
  event_type : String,
  schema_json : String,
  require_cloudevents : Bool,
) -> Array[ContractIssue] {
  let issues : Array[ContractIssue] = []
  let root = try @json.parse(payload) catch {
    _ => {
      event_issue(issues, "invalid_json", "$")
      return issues
    }
  } noraise {
    parsed => parsed
  }
  let mut data = root
  if require_cloudevents || media_type == "application/cloudevents+json" {
    if media_type != "application/cloudevents+json" {
      event_issue(issues, "unsupported_media_type", "content-type")
      return issues
    }
    if event_text(root, "specversion") != Some("1.0") ||
      event_text(root, "id").unwrap_or("").is_empty() ||
      event_text(root, "source").unwrap_or("").is_empty() ||
      event_text(root, "type") != Some(event_type) ||
      event_field(root, "data_base64") is Some(_) {
      event_issue(issues, "invalid_cloudevent", "$")
      return issues
    }
    data = event_field(root, "data").unwrap_or(Json::null())
  }
  if !schema_json.is_empty() {
    let schema = try @json.parse(schema_json) catch {
      _ => {
        event_issue(issues, "invalid_schema", "schema")
        return issues
      }
    } noraise {
      parsed => parsed
    }
    validate_schema_value(schema, data, "$", 0, issues)
  }
  issues
}
