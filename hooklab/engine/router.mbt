///|
pub(all) enum MatchOperator {
  Equals
  NotEquals
  Exists
  Contains
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
