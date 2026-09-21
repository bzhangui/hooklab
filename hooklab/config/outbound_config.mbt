///|
fn enabled_field(
  root : Json,
  name : String,
  location : String,
  issues : Array[ConfigIssue],
) -> Bool {
  match field(root, name) {
    None => true
    Some(True) => true
    Some(False) => false
    Some(_) => {
      add_issue(
        issues,
        "invalid_enabled",
        location + "." + name,
        "The enabled field must be a boolean.",
      )
      false
    }
  }
}

///|
fn required_text(
  root : Json,
  name : String,
  location : String,
  code : String,
  message : String,
  issues : Array[ConfigIssue],
) -> String {
  let value = text_field(root, name).unwrap_or("").trim().to_owned()
  if value.is_empty() {
    add_issue(issues, code, location + "." + name, message)
  }
  value
}

///|
fn outbound_id_exists(values : Array[String], value : String) -> Bool {
  values.contains(value)
}

///|
fn outbound_url_forbidden_char(c : Char) -> Bool {
  let code = c.to_int()
  code <= 0x20 || code == 0x7F || c == '@' || c == '?' || c == '#' || c == '\\'
}

///|
fn outbound_url_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn outbound_url_host_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  outbound_url_digit(c) ||
  c == '-' ||
  c == '.'
}

///|
fn outbound_url_port_valid(chars : Array[Char], start : Int, end : Int) -> Bool {
  if start >= end {
    return false
  }
  let mut port = 0
  for i = start; i < end; i = i + 1 {
    let c = chars[i]
    if !outbound_url_digit(c) {
      return false
    }
    port = port * 10 + c.to_int() - '0'.to_int()
    if port > 65535 {
      return false
    }
  }
  port > 0
}

///|
fn outbound_endpoint_url_valid(value : String) -> Bool {
  let authority_start = if value.has_prefix("http://") {
    7
  } else if value.has_prefix("https://") {
    8
  } else {
    return false
  }
  let chars = value.to_array()
  for c in chars {
    if outbound_url_forbidden_char(c) {
      return false
    }
  }
  let mut authority_end = chars.length()
  for i = authority_start; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      authority_end = i
      break
    }
  }
  if authority_start >= authority_end {
    return false
  }
  if chars[authority_start] == '[' {
    let mut closing = -1
    for i = authority_start + 1; i < authority_end; i = i + 1 {
      if chars[i] == ']' {
        closing = i
        break
      }
    }
    if closing <= authority_start + 1 {
      return false
    }
    let mut has_colon = false
    for i = authority_start + 1; i < closing; i = i + 1 {
      let c = chars[i]
      if c == ':' {
        has_colon = true
      } else if !outbound_url_digit(c) &&
        !(c >= 'a' && c <= 'f') &&
        !(c >= 'A' && c <= 'F') &&
        c != '.' {
        return false
      }
    }
    if !has_colon {
      return false
    }
    if closing + 1 == authority_end {
      return true
    }
    closing + 1 < authority_end &&
    chars[closing + 1] == ':' &&
    outbound_url_port_valid(chars, closing + 2, authority_end)
  } else {
    let mut port_separator = -1
    for i = authority_start; i < authority_end; i = i + 1 {
      let c = chars[i]
      if c == ':' {
        if port_separator >= 0 {
          return false
        }
        port_separator = i
      } else if !outbound_url_host_char(c) {
        return false
      }
    }
    let host_end = if port_separator >= 0 {
      port_separator
    } else {
      authority_end
    }
    if host_end <= authority_start ||
      chars[authority_start] == '.' ||
      chars[host_end - 1] == '.' {
      return false
    }
    if port_separator >= 0 {
      outbound_url_port_valid(chars, port_separator + 1, authority_end)
    } else {
      true
    }
  }
}

///|
fn parse_event_types(
  root : Json,
  location : String,
  issues : Array[ConfigIssue],
) -> Array[String] {
  let values : Array[String] = []
  match field(root, "event_types") {
    Some(Array(items)) => {
      for i = 0; i < items.length(); i = i + 1 {
        match items[i] {
          String(value) => {
            let trimmed = value.trim().to_owned()
            if trimmed.is_empty() {
              add_issue(
                issues,
                "invalid_event_type",
                location + ".event_types[" + i.to_string() + "]",
                "Event types cannot be empty.",
              )
            } else if trimmed != "*" && !@outbound.delivery_token_valid(trimmed) {
              add_issue(
                issues,
                "invalid_event_type",
                location + ".event_types[" + i.to_string() + "]",
                "Event types must use only letters, digits, dot, underscore, hyphen, colon, or slash; use * only as the complete wildcard.",
              )
            } else if values.contains(trimmed) {
              add_issue(
                issues,
                "duplicate_event_type",
                location + ".event_types[" + i.to_string() + "]",
                "Event types must be unique within a subscription.",
              )
            } else {
              values.push(trimmed)
            }
          }
          _ =>
            add_issue(
              issues,
              "invalid_event_type",
              location + ".event_types[" + i.to_string() + "]",
              "Every event type must be a string.",
            )
        }
      }
      if values.is_empty() {
        add_issue(
          issues,
          "missing_event_types",
          location + ".event_types",
          "At least one event type or wildcard is required.",
        )
      }
    }
    _ =>
      add_issue(
        issues,
        "missing_event_types",
        location + ".event_types",
        "The event_types field must be a non-empty array.",
      )
  }
  values
}

///|
fn parse_outbound_config(
  root : Json,
  issues : Array[ConfigIssue],
) -> (
  Array[@outbound.Application],
  Array[@outbound.Endpoint],
  Array[@outbound.Subscription],
) {
  let applications : Array[@outbound.Application] = []
  let endpoints : Array[@outbound.Endpoint] = []
  let subscriptions : Array[@outbound.Subscription] = []
  let application_ids : Array[String] = []
  let endpoint_ids : Array[String] = []
  let subscription_ids : Array[String] = []
  guard field(root, "outbound") is Some(outbound) else {
    return (applications, endpoints, subscriptions)
  }
  guard outbound is Object(_) else {
    add_issue(
      issues, "invalid_outbound", "outbound", "The outbound field must be an object.",
    )
    return (applications, endpoints, subscriptions)
  }
  match field(outbound, "applications") {
    Some(Array(items)) =>
      for i = 0; i < items.length(); i = i + 1 {
        let location = "outbound.applications[" + i.to_string() + "]"
        let item = items[i]
        if item is Object(_) {
          if field(item, "publish_token") is Some(_) ||
            field(item, "token") is Some(_) {
            add_issue(
              issues,
              "inline_secret_forbidden",
              location + ".publish_token",
              "Store publisher tokens in environment variables, not configuration.",
            )
          }
          let id = required_text(
            item, "id", location, "missing_application_id", "Every outbound application requires a non-empty id.",
            issues,
          )
          let token_env = required_text(
            item, "publish_token_env", location, "missing_publish_token_env", "Every outbound application requires a publisher-token environment variable.",
            issues,
          )
          if outbound_id_exists(application_ids, id) {
            add_issue(
              issues,
              "duplicate_application_id",
              location + ".id",
              "Outbound application ids must be unique.",
            )
          } else if !id.is_empty() {
            application_ids.push(id)
          }
          if !id.is_empty() && !token_env.is_empty() {
            applications.push({
              id,
              publish_token_env: token_env,
              enabled: enabled_field(item, "enabled", location, issues),
            })
          }
        } else {
          add_issue(
            issues, "invalid_application", location, "Every outbound application must be an object.",
          )
        }
      }
    _ =>
      add_issue(
        issues, "missing_outbound_applications", "outbound.applications", "Outbound configuration requires a non-empty applications array.",
      )
  }
  match field(outbound, "endpoints") {
    Some(Array(items)) =>
      for i = 0; i < items.length(); i = i + 1 {
        let location = "outbound.endpoints[" + i.to_string() + "]"
        let item = items[i]
        if item is Object(_) {
          if field(item, "signing_secret") is Some(_) ||
            field(item, "secret") is Some(_) {
            add_issue(
              issues,
              "inline_secret_forbidden",
              location + ".signing_secret",
              "Store endpoint signing secrets in environment variables, not configuration.",
            )
          }
          let id = required_text(
            item, "id", location, "missing_endpoint_id", "Every outbound endpoint requires a non-empty id.",
            issues,
          )
          let url = required_text(
            item, "url", location, "missing_endpoint_url", "Every outbound endpoint requires a URL.",
            issues,
          )
          let raw_url = text_field(item, "url").unwrap_or("")
          let url_valid = !url.is_empty() &&
            raw_url == url &&
            outbound_endpoint_url_valid(url)
          if !url.is_empty() && !url_valid {
            add_issue(
              issues,
              "invalid_endpoint_url",
              location + ".url",
              "The outbound endpoint must be a safe HTTP(S) URL with a host and optional valid port, without credentials, query, fragment, backslash, control characters, or whitespace.",
            )
          }
          let secret_env = required_text(
            item, "signing_secret_env", location, "missing_signing_secret_env", "Every outbound endpoint requires a signing-secret environment variable.",
            issues,
          )
          let key_id = required_text(
            item, "key_id", location, "missing_key_id", "Every outbound endpoint requires a public key id.",
            issues,
          )
          if !key_id.is_empty() && !@outbound.delivery_token_valid(key_id) {
            add_issue(
              issues,
              "invalid_key_id",
              location + ".key_id",
              "The public key id must be a delivery-safe token of at most 128 characters.",
            )
          }
          if outbound_id_exists(endpoint_ids, id) {
            add_issue(
              issues,
              "duplicate_endpoint_id",
              location + ".id",
              "Outbound endpoint ids must be unique.",
            )
          } else if !id.is_empty() {
            endpoint_ids.push(id)
          }
          if !id.is_empty() &&
            !url.is_empty() &&
            url_valid &&
            !secret_env.is_empty() &&
            !key_id.is_empty() &&
            @outbound.delivery_token_valid(key_id) {
            endpoints.push({
              id,
              url,
              signing_secret_env: secret_env,
              key_id,
              enabled: enabled_field(item, "enabled", location, issues),
            })
          }
        } else {
          add_issue(
            issues, "invalid_endpoint", location, "Every outbound endpoint must be an object.",
          )
        }
      }
    _ =>
      add_issue(
        issues, "missing_outbound_endpoints", "outbound.endpoints", "Outbound configuration requires a non-empty endpoints array.",
      )
  }
  match field(outbound, "subscriptions") {
    Some(Array(items)) =>
      for i = 0; i < items.length(); i = i + 1 {
        let location = "outbound.subscriptions[" + i.to_string() + "]"
        let item = items[i]
        if item is Object(_) {
          let id = required_text(
            item, "id", location, "missing_subscription_id", "Every outbound subscription requires a non-empty id.",
            issues,
          )
          let application_id = required_text(
            item, "application", location, "missing_subscription_application", "Every outbound subscription requires an application reference.",
            issues,
          )
          let endpoint_id = required_text(
            item, "endpoint", location, "missing_subscription_endpoint", "Every outbound subscription requires an endpoint reference.",
            issues,
          )
          let event_types = parse_event_types(item, location, issues)
          if outbound_id_exists(subscription_ids, id) {
            add_issue(
              issues,
              "duplicate_subscription_id",
              location + ".id",
              "Outbound subscription ids must be unique.",
            )
          } else if !id.is_empty() {
            subscription_ids.push(id)
          }
          if !application_id.is_empty() &&
            !application_ids.contains(application_id) {
            add_issue(
              issues,
              "unknown_subscription_application",
              location + ".application",
              "The subscription references an unknown application.",
            )
          }
          if !endpoint_id.is_empty() && !endpoint_ids.contains(endpoint_id) {
            add_issue(
              issues,
              "unknown_subscription_endpoint",
              location + ".endpoint",
              "The subscription references an unknown endpoint.",
            )
          }
          if !id.is_empty() &&
            !application_id.is_empty() &&
            !endpoint_id.is_empty() &&
            !event_types.is_empty() {
            subscriptions.push({
              id,
              application_id,
              endpoint_id,
              event_types,
              enabled: enabled_field(item, "enabled", location, issues),
            })
          }
        } else {
          add_issue(
            issues, "invalid_subscription", location, "Every outbound subscription must be an object.",
          )
        }
      }
    _ =>
      add_issue(
        issues, "missing_outbound_subscriptions", "outbound.subscriptions", "Outbound configuration requires a non-empty subscriptions array.",
      )
  }
  if applications.is_empty() {
    add_issue(
      issues, "missing_outbound_applications", "outbound.applications", "At least one valid outbound application is required.",
    )
  }
  if endpoints.is_empty() {
    add_issue(
      issues, "missing_outbound_endpoints", "outbound.endpoints", "At least one valid outbound endpoint is required.",
    )
  }
  if subscriptions.is_empty() {
    add_issue(
      issues, "missing_outbound_subscriptions", "outbound.subscriptions", "At least one valid outbound subscription is required.",
    )
  }
  (applications, endpoints, subscriptions)
}
