///|
/// A bounded, deterministic JSON transformation operation. Destination paths
/// use the same dot notation as routing rules. `SetValue` may add a leaf to an
/// existing object; parent containers must already exist.
pub(all) enum TransformOperation {
  SetValue(String, Json)
  Remove(String)
  Copy(String, String)
} derive(Eq, Debug)

///|
/// Hard limits applied before and after executing a transformation plan.
pub(all) struct TransformBudget {
  max_input_bytes : Int
  max_output_bytes : Int
  max_operations : Int
} derive(Eq, Debug)

///|
pub fn TransformBudget::safe_default() -> TransformBudget {
  { max_input_bytes: 262144, max_output_bytes: 262144, max_operations: 16, }
}

///|
/// A route name binds a transformation plan to an existing routing rule.
pub(all) struct RouteTransform {
  route_name : String
  operations : Array[TransformOperation]
  budget : TransformBudget
} derive(Eq, Debug)

///|
pub(all) enum TransformFailureCode {
  InvalidBudget
  InvalidJson
  InputTooLarge
  OperationLimitExceeded
  InvalidPath
  PathNotFound
  OutputTooLarge
} derive(Eq, Debug)

///|
pub(all) struct TransformFailure {
  code : TransformFailureCode
  operation_index : Int?
  path : String
  message : String
} derive(Eq, Debug)

///|
pub(all) enum TransformResult {
  Transformed(String, Int)
  TransformRejected(TransformFailure)
} derive(Eq, Debug)

///|
pub fn failure_code_name(code : TransformFailureCode) -> String {
  match code {
    InvalidBudget => "invalid_budget"
    InvalidJson => "invalid_json"
    InputTooLarge => "input_too_large"
    OperationLimitExceeded => "operation_limit_exceeded"
    InvalidPath => "invalid_path"
    PathNotFound => "path_not_found"
    OutputTooLarge => "output_too_large"
  }
}

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
fn path_parts(path : String) -> Array[String]? {
  let trimmed = path.trim().to_owned()
  if trimmed == "$" {
    return Some([])
  }
  let normalized = if trimmed.has_prefix("$.") {
    trimmed[2:].to_owned()
  } else {
    trimmed
  }
  if normalized.is_empty() {
    return None
  }
  let parts : Array[String] = []
  for part in normalized.split(".") {
    let value = part.to_owned()
    if value.is_empty() {
      return None
    }
    parts.push(value)
  }
  Some(parts)
}

///|
pub fn valid_path(path : String) -> Bool {
  path_parts(path) is Some(_)
}

///|
fn json_at_path(root : Json, parts : Array[String]) -> Json? {
  let mut current = root
  for part in parts {
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
priv enum EditResult {
  Edited(Json)
  EditMissing
}

///|
fn set_at_path(
  current : Json,
  parts : Array[String],
  index : Int,
  value : Json,
) -> EditResult {
  if index >= parts.length() {
    return Edited(value)
  }
  let part = parts[index]
  match current {
    Object(values) => {
      let updated : Map[String, Json] = Map([])
      for key, child in values {
        updated.set(key, child)
      }
      if index == parts.length() - 1 {
        updated.set(part, value)
        Edited(Json::object(updated))
      } else {
        guard values.get_from_string(part) is Some(child) else {
          return EditMissing
        }
        match set_at_path(child, parts, index + 1, value) {
          Edited(next) => {
            updated.set(part, next)
            Edited(Json::object(updated))
          }
          EditMissing => EditMissing
        }
      }
    }
    Array(values) =>
      match parse_array_index(part) {
        Some(array_index) if array_index < values.length() => {
          let updated = values.copy()
          if index == parts.length() - 1 {
            updated[array_index] = value
            Edited(Json::array(updated))
          } else {
            match set_at_path(values[array_index], parts, index + 1, value) {
              Edited(next) => {
                updated[array_index] = next
                Edited(Json::array(updated))
              }
              EditMissing => EditMissing
            }
          }
        }
        _ => EditMissing
      }
    _ => EditMissing
  }
}

///|
fn remove_at_path(
  current : Json,
  parts : Array[String],
  index : Int,
) -> EditResult {
  if index >= parts.length() {
    return EditMissing
  }
  let part = parts[index]
  match current {
    Object(values) => {
      guard values.get_from_string(part) is Some(child) else {
        return EditMissing
      }
      let updated : Map[String, Json] = Map([])
      for key, value in values {
        if !(index == parts.length() - 1 && key == part) {
          updated.set(key, value)
        }
      }
      if index == parts.length() - 1 {
        Edited(Json::object(updated))
      } else {
        match remove_at_path(child, parts, index + 1) {
          Edited(next) => {
            updated.set(part, next)
            Edited(Json::object(updated))
          }
          EditMissing => EditMissing
        }
      }
    }
    Array(values) =>
      match parse_array_index(part) {
        Some(array_index) if array_index < values.length() => {
          let updated = values.copy()
          if index == parts.length() - 1 {
            ignore(updated.remove(array_index))
            Edited(Json::array(updated))
          } else {
            match remove_at_path(values[array_index], parts, index + 1) {
              Edited(next) => {
                updated[array_index] = next
                Edited(Json::array(updated))
              }
              EditMissing => EditMissing
            }
          }
        }
        _ => EditMissing
      }
    _ => EditMissing
  }
}

///|
fn operation_path(operation : TransformOperation) -> String {
  match operation {
    SetValue(path, _) | Remove(path) => path
    Copy(_, path) => path
  }
}

///|
fn rejection(
  code : TransformFailureCode,
  operation_index : Int?,
  path : String,
  message : String,
) -> TransformResult {
  TransformRejected({ code, operation_index, path, message, })
}

///|
/// Applies a transformation atomically. A rejected plan never returns a
/// partial document, so callers cannot accidentally deliver half-transformed
/// or untransformed input after a policy failure.
pub fn apply(
  body : String,
  operations : Array[TransformOperation],
  budget : TransformBudget,
) -> TransformResult {
  if budget.max_input_bytes <= 0 ||
    budget.max_output_bytes <= 0 ||
    budget.max_operations <= 0 {
    return rejection(
      InvalidBudget,
      None,
      "$",
      "Transformation budgets must be positive.",
    )
  }
  let input_bytes = @utf8.encode(body[:]).length()
  if input_bytes > budget.max_input_bytes {
    return rejection(
      InputTooLarge,
      None,
      "$",
      "The input exceeds the configured transformation byte budget.",
    )
  }
  if operations.length() > budget.max_operations {
    return rejection(
      OperationLimitExceeded,
      None,
      "$",
      "The transformation plan exceeds the configured operation budget.",
    )
  }
  let mut root = try @json.parse(body) catch {
    _ =>
      return rejection(
        InvalidJson,
        None,
        "$",
        "Only valid JSON payloads can be transformed.",
      )
  } noraise {
    value => value
  }
  for i = 0; i < operations.length(); i = i + 1 {
    let operation = operations[i]
    let path = operation_path(operation)
    guard path_parts(path) is Some(parts) else {
      return rejection(
        InvalidPath,
        Some(i),
        path,
        "The transformation path is invalid.",
      )
    }
    let result = match operation {
      SetValue(_, value) => set_at_path(root, parts, 0, value)
      Remove(_) =>
        if parts.is_empty() {
          EditMissing
        } else {
          remove_at_path(root, parts, 0)
        }
      Copy(source, _) => {
        guard path_parts(source) is Some(source_parts) else {
          return rejection(
            InvalidPath,
            Some(i),
            source,
            "The transformation source path is invalid.",
          )
        }
        match json_at_path(root, source_parts) {
          Some(value) => set_at_path(root, parts, 0, value)
          None => EditMissing
        }
      }
    }
    match result {
      Edited(next) => root = next
      EditMissing =>
        return rejection(
          PathNotFound,
          Some(i),
          path,
          "The transformation path or one of its parents does not exist.",
        )
    }
  }
  let output = root.stringify()
  if @utf8.encode(output[:]).length() > budget.max_output_bytes {
    return rejection(
      OutputTooLarge,
      None,
      "$",
      "The transformed output exceeds the configured byte budget.",
    )
  }
  Transformed(output, operations.length())
}
