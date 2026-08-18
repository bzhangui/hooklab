///|
pub(all) enum MatchOperator {
  Equals
  NotEquals
  Exists
  Contains
  StartsWith
  EndsWith
} derive(Eq, Debug)

///|
pub(all) struct RouteRule {
  name : String
  path : String
  operator : MatchOperator
  expected : String
  target : String
} derive(Eq, Debug)

///|
pub(all) struct RouteMatch {
  rule_name : String
  target : String
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
    index = index * 10 + (c.to_int() - '0'.to_int())
  }
  Some(index)
}

///|
fn json_at_path(root : Json, path : String) -> Json? {
  let mut current = root
  let normalized = if path.has_prefix("$.") {
    path[2:].to_owned()
  } else {
    path
  }
  if normalized == "$" || normalized.is_empty() {
    return Some(current)
  }
  for part_view in normalized.split(".") {
    let part = part_view.to_owned()
    match current {
      Object(values) =>
        match values.get_from_string(part) {
          Some(next) => current = next
          None => return None
        }
      Array(values) =>
        match parse_array_index(part) {
          Some(index) if index < values.length() => current = values[index]
          _ => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
fn json_scalar(value : Json) -> String? {
  match value {
    String(text) => Some(text)
    Number(number, ..) => Some(number.to_string())
    True => Some("true")
    False => Some("false")
    Null => Some("null")
    _ => None
  }
}

///|
fn rule_matches(root : Json, rule : RouteRule) -> Bool {
  let actual = json_at_path(root, rule.path)
  let scalar = match actual {
    Some(value) => json_scalar(value).unwrap_or("")
    None => ""
  }
  match rule.operator {
    Exists => actual is Some(_)
    Equals => scalar == rule.expected
    NotEquals => scalar != rule.expected
    Contains => scalar.contains(rule.expected)
    StartsWith => scalar.has_prefix(rule.expected)
    EndsWith => scalar.has_suffix(rule.expected)
  }
}

///|
pub fn route(body : String, rules : Array[RouteRule]) -> Array[RouteMatch] {
  try @json.parse(body) catch {
    _ => []
  } noraise {
    parsed => {
      let matches : Array[RouteMatch] = []
      for rule in rules {
        if rule_matches(parsed, rule) {
          matches.push({ rule_name: rule.name, target: rule.target })
        }
      }
      matches
    }
  }
}
