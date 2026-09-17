///|
fn transform_path_field(
  root : Json,
  name : String,
  location : String,
  issues : Array[ConfigIssue],
) -> String? {
  match field(root, name) {
    Some(String(value)) => {
      let path = value.trim().to_owned()
      if @transform.valid_path(path) {
        Some(path)
      } else {
        add_issue(
          issues,
          "invalid_transform_path",
          location + "." + name,
          "Use a non-empty JSON dot path such as customer.email or $.",
        )
        None
      }
    }
    _ => {
      add_issue(
        issues,
        "invalid_transform_path",
        location + "." + name,
        "A transformation path must be a string.",
      )
      None
    }
  }
}

///|
fn transform_budget_field(
  root : Json,
  name : String,
  location : String,
  maximum : Int,
  issues : Array[ConfigIssue],
) -> Int {
  match integer_field(root, name) {
    Some(value) if value > 0 && value <= maximum => value
    _ => {
      add_issue(
        issues,
        "invalid_transform_budget",
        location + "." + name,
        "The transformation budget must be a positive integer no greater than " +
        maximum.to_string() +
        ".",
      )
      0
    }
  }
}

///|
fn parse_transform_operation(
  item : Json,
  location : String,
  issues : Array[ConfigIssue],
) -> @transform.TransformOperation? {
  guard item is Object(_) else {
    add_issue(
      issues, "invalid_transform_operation", location, "Every transformation operation must be a JSON object.",
    )
    return None
  }
  let start = issues.length()
  let operation = text_field(item, "operation")
    .map(value => @core.ascii_lower(value.trim().to_owned()))
    .unwrap_or("")
  let path = transform_path_field(item, "path", location, issues)
  let mut parsed : @transform.TransformOperation? = None
  match operation {
    "set" =>
      match (path, field(item, "value")) {
        (Some(destination), Some(value)) =>
          parsed = Some(@transform.SetValue(destination, value))
        (_, None) =>
          add_issue(
            issues,
            "missing_transform_value",
            location + ".value",
            "The set operation requires a JSON value.",
          )
        _ => ()
      }
    "remove" =>
      match path {
        Some("$") =>
          add_issue(
            issues,
            "invalid_transform_path",
            location + ".path",
            "The remove operation cannot delete the document root.",
          )
        Some(destination) => parsed = Some(@transform.Remove(destination))
        None => ()
      }
    "copy" => {
      let source = transform_path_field(item, "from", location, issues)
      match (source, path) {
        (Some(from), Some(destination)) =>
          parsed = Some(@transform.Copy(from, destination))
        _ => ()
      }
    }
    "" =>
      add_issue(
        issues,
        "missing_transform_operation",
        location + ".operation",
        "Every transformation operation requires a name.",
      )
    _ =>
      add_issue(
        issues,
        "unsupported_transform_operation",
        location + ".operation",
        "Use set, remove, or copy.",
      )
  }
  if issues.length() == start {
    parsed
  } else {
    None
  }
}

///|
fn parse_route_transform(
  route : Json,
  route_name : String,
  route_location : String,
  issues : Array[ConfigIssue],
) -> @transform.RouteTransform? {
  guard field(route, "transform") is Some(value) else { return None }
  let location = route_location + ".transform"
  guard value is Object(_) else {
    add_issue(
      issues, "invalid_transform", location, "A route transform must be a JSON object.",
    )
    return None
  }
  let start = issues.length()
  let max_input_bytes = transform_budget_field(
    value, "max_input_bytes", location, 1048576, issues,
  )
  let max_output_bytes = transform_budget_field(
    value, "max_output_bytes", location, 1048576, issues,
  )
  let max_operations = transform_budget_field(
    value, "max_operations", location, 64, issues,
  )
  let operations : Array[@transform.TransformOperation] = []
  match field(value, "operations") {
    Some(Array(items)) => {
      if items.is_empty() {
        add_issue(
          issues,
          "missing_transform_operations",
          location + ".operations",
          "A route transform requires at least one operation.",
        )
      }
      for i = 0; i < items.length(); i = i + 1 {
        match
          parse_transform_operation(
            items[i],
            location + ".operations[" + i.to_string() + "]",
            issues,
          ) {
          Some(operation) => operations.push(operation)
          None => ()
        }
      }
    }
    _ =>
      add_issue(
        issues,
        "missing_transform_operations",
        location + ".operations",
        "The operations field must be a non-empty array.",
      )
  }
  if max_operations > 0 && operations.length() > max_operations {
    add_issue(
      issues,
      "transform_operation_budget_exceeded",
      location + ".operations",
      "The configured operations exceed max_operations.",
    )
  }
  if issues.length() == start {
    Some({
      route_name,
      operations,
      budget: { max_input_bytes, max_output_bytes, max_operations, },
    })
  } else {
    None
  }
}
