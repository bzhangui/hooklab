///|
pub(all) struct GatewayConfig {
  version : Int
  provider : @core.Provider
  secret_env : String
  previous_secrets_env : String?
  port : Int
  data_dir : String
  routes : Array[@engine.RouteRule]
  route_transforms : Array[@transform.RouteTransform]
  delivery_limits : Array[@delivery.TargetLimit]
  circuit_breakers : Array[@delivery.CircuitPolicy]
  outbound_applications : Array[@outbound.Application]
  outbound_endpoints : Array[@outbound.Endpoint]
  outbound_subscriptions : Array[@outbound.Subscription]
} derive(Eq, Debug)

///|
pub(all) struct ConfigIssue {
  code : String
  location : String
  message : String
} derive(Eq, Debug)

///|
pub(all) enum ConfigResult {
  ConfigLoaded(GatewayConfig)
  ConfigInvalid(Array[ConfigIssue])
} derive(Eq, Debug)

///|
fn field(root : Json, name : String) -> Json? {
  match root {
    Object(values) => values.get_from_string(name)
    _ => None
  }
}

///|
fn text_field(root : Json, name : String) -> String? {
  match field(root, name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn integer_field(root : Json, name : String) -> Int? {
  match field(root, name) {
    Some(Number(value, ..)) if value == value.trunc() => Some(value.to_int())
    _ => None
  }
}

///|
fn provider_from_name(value : String) -> @core.Provider? {
  match @core.ascii_lower(@core.trim_ascii(value)) {
    "github" => Some(@core.GitHub)
    "stripe" => Some(@core.Stripe)
    "feishu" | "lark" => Some(@core.Feishu)
    "generic" | "generic-hmac" => Some(@core.GenericHmac)
    _ => None
  }
}

///|
fn operator_from_name(value : String) -> @engine.MatchOperator? {
  match @core.ascii_lower(@core.trim_ascii(value)) {
    "equals" => Some(@engine.Equals)
    "not-equals" | "not_equals" => Some(@engine.NotEquals)
    "exists" => Some(@engine.Exists)
    "contains" => Some(@engine.Contains)
    "starts-with" | "starts_with" => Some(@engine.StartsWith)
    "ends-with" | "ends_with" => Some(@engine.EndsWith)
    _ => None
  }
}

///|
fn add_issue(
  issues : Array[ConfigIssue],
  code : String,
  location : String,
  message : String,
) -> Unit {
  issues.push({ code, location, message, })
}

///|
/// Parses a versioned gateway configuration without accepting inline secrets.
/// Every validation issue is returned so operators can repair a file in one
/// iteration before attempting to start the gateway.
pub fn parse_gateway_config(text : String) -> ConfigResult {
  let root = try @json.parse(text) catch {
    _ =>
      return ConfigInvalid([
        {
          code: "invalid_json",
          location: "$",
          message: "The configuration is not valid JSON.",
        },
      ])
  } noraise {
    value => value
  }
  guard root is Object(_) else {
    return ConfigInvalid([
      {
        code: "invalid_root",
        location: "$",
        message: "The configuration root must be a JSON object.",
      },
    ])
  }
  let issues : Array[ConfigIssue] = []
  let version = integer_field(root, "version").unwrap_or(0)
  if version != 1 {
    add_issue(
      issues, "unsupported_version", "version", "Only gateway configuration version 1 is supported.",
    )
  }
  let mut provider : @core.Provider? = None
  match text_field(root, "provider") {
    Some(value) =>
      match provider_from_name(value) {
        Some(parsed) => provider = Some(parsed)
        None =>
          add_issue(
            issues, "unsupported_provider", "provider", "Use github, stripe, feishu, or generic-hmac.",
          )
      }
    None =>
      add_issue(
        issues, "missing_provider", "provider", "A provider name is required.",
      )
  }
  if field(root, "secret") is Some(_) || field(root, "secrets") is Some(_) {
    add_issue(
      issues, "inline_secret_forbidden", "secret", "Store secret values in environment variables, not in configuration.",
    )
  }
  let secret_env = match field(root, "secret_env") {
    None => "HOOKLAB_SECRET"
    Some(String(value)) => {
      let trimmed = @core.trim_ascii(value)
      if trimmed.is_empty() {
        add_issue(
          issues, "invalid_secret_env", "secret_env", "The primary secret environment variable name cannot be empty.",
        )
      }
      trimmed
    }
    _ => {
      add_issue(
        issues, "invalid_secret_env", "secret_env", "The primary secret environment variable name must be a string.",
      )
      ""
    }
  }
  let previous_secrets_env : String? = match
    field(root, "previous_secrets_env") {
    None => Some("HOOKLAB_PREVIOUS_SECRETS")
    Some(Null) => None
    Some(String(value)) => {
      let trimmed = @core.trim_ascii(value)
      if trimmed.is_empty() {
        None
      } else {
        Some(trimmed)
      }
    }
    _ => {
      add_issue(
        issues, "invalid_previous_secrets_env", "previous_secrets_env", "The previous-secret environment variable name must be a string or null.",
      )
      None
    }
  }
  let port = match field(root, "port") {
    None => 8787
    Some(_) =>
      match integer_field(root, "port") {
        Some(value) if value > 0 && value <= 65535 => value
        _ => {
          add_issue(
            issues, "invalid_port", "port", "The port must be an integer from 1 through 65535.",
          )
          8787
        }
      }
  }
  let data_dir = match field(root, "data_dir") {
    None => ".hooklab-data"
    Some(String(value)) => {
      let trimmed = @core.trim_ascii(value)
      if trimmed.is_empty() {
        add_issue(
          issues, "invalid_data_dir", "data_dir", "The data directory cannot be empty.",
        )
      }
      trimmed
    }
    _ => {
      add_issue(
        issues, "invalid_data_dir", "data_dir", "The data directory must be a string.",
      )
      ""
    }
  }
  let routes : Array[@engine.RouteRule] = []
  let route_transforms : Array[@transform.RouteTransform] = []
  let route_names : Array[String] = []
  match field(root, "routes") {
    Some(Array(items)) => {
      if items.is_empty() {
        add_issue(
          issues, "missing_routes", "routes", "At least one route is required.",
        )
      }
      for i = 0; i < items.length(); i = i + 1 {
        let location = "routes[" + i.to_string() + "]"
        let item = items[i]
        if item is Object(_) {
          let mut valid = true
          let name = text_field(item, "name").unwrap_or("").trim().to_owned()
          if name.is_empty() {
            valid = false
            add_issue(
              issues,
              "missing_route_name",
              location + ".name",
              "Every route requires a non-empty name.",
            )
          } else if route_names.contains(name) {
            valid = false
            add_issue(
              issues,
              "duplicate_route_name",
              location + ".name",
              "Route names must be unique.",
            )
          } else {
            route_names.push(name)
          }
          let path = match field(item, "path") {
            None => "$"
            Some(String(value)) if !value.trim().is_empty() =>
              value.trim().to_owned()
            _ => {
              valid = false
              add_issue(
                issues,
                "invalid_route_path",
                location + ".path",
                "A route path must be a non-empty JSON dot path.",
              )
              ""
            }
          }
          let mut operator : @engine.MatchOperator? = None
          match text_field(item, "operator") {
            Some(value) =>
              match operator_from_name(value) {
                Some(parsed) => operator = Some(parsed)
                None => {
                  valid = false
                  add_issue(
                    issues,
                    "unsupported_operator",
                    location + ".operator",
                    "Use equals, not-equals, exists, contains, starts-with, or ends-with.",
                  )
                }
              }
            None => {
              valid = false
              add_issue(
                issues,
                "missing_operator",
                location + ".operator",
                "Every route requires a match operator.",
              )
            }
          }
          let expected_value = field(item, "expected")
          let expected = match expected_value {
            Some(String(value)) => value
            Some(_) => {
              valid = false
              add_issue(
                issues,
                "invalid_expected",
                location + ".expected",
                "The expected route value must be a string.",
              )
              ""
            }
            None => ""
          }
          match operator {
            Some(@engine.Exists) => ()
            Some(_) if expected_value is None => {
              valid = false
              add_issue(
                issues,
                "missing_expected",
                location + ".expected",
                "This route operator requires an expected string.",
              )
            }
            _ => ()
          }
          let target = text_field(item, "target")
            .unwrap_or("")
            .trim()
            .to_owned()
          if !(target.has_prefix("http://") || target.has_prefix("https://")) {
            valid = false
            add_issue(
              issues,
              "invalid_target",
              location + ".target",
              "The delivery target must use HTTP or HTTPS.",
            )
          }
          if valid {
            match operator {
              Some(parsed) => {
                routes.push({ name, path, operator: parsed, expected, target, })
                match parse_route_transform(item, name, location, issues) {
                  Some(plan) => route_transforms.push(plan)
                  None => ()
                }
              }
              None => ()
            }
          }
        } else {
          add_issue(
            issues, "invalid_route", location, "Every route must be a JSON object.",
          )
        }
      }
    }
    _ =>
      add_issue(
        issues, "missing_routes", "routes", "The routes field must be a non-empty array.",
      )
  }
  let delivery_limits = parse_delivery_limits(root, routes, issues)
  let circuit_breakers = parse_circuit_breakers(root, routes, issues)
  let (outbound_applications, outbound_endpoints, outbound_subscriptions) = parse_outbound_config(
    root, issues,
  )
  if issues.is_empty() {
    match provider {
      Some(parsed) =>
        ConfigLoaded({
          version,
          provider: parsed,
          secret_env,
          previous_secrets_env,
          port,
          data_dir,
          routes,
          route_transforms,
          delivery_limits,
          circuit_breakers,
          outbound_applications,
          outbound_endpoints,
          outbound_subscriptions,
        })
      None => ConfigInvalid(issues)
    }
  } else {
    ConfigInvalid(issues)
  }
}

///|
fn json_escape(value : String) -> String {
  let out = StringBuilder()
  for c in value {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
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
pub fn config_result_json(result : ConfigResult) -> String {
  match result {
    ConfigLoaded(value) =>
      "{\"valid\":true,\"version\":" +
      value.version.to_string() +
      ",\"provider\":" +
      json_string(@core.provider_name(value.provider)) +
      ",\"port\":" +
      value.port.to_string() +
      ",\"data_dir\":" +
      json_string(value.data_dir) +
      ",\"secret_env\":" +
      json_string(value.secret_env) +
      ",\"routes\":" +
      value.routes.length().to_string() +
      ",\"transforms\":" +
      value.route_transforms.length().to_string() +
      ",\"delivery_limits\":" +
      value.delivery_limits.length().to_string() +
      ",\"circuit_breakers\":" +
      value.circuit_breakers.length().to_string() +
      ",\"outbound_applications\":" +
      value.outbound_applications.length().to_string() +
      ",\"outbound_endpoints\":" +
      value.outbound_endpoints.length().to_string() +
      ",\"outbound_subscriptions\":" +
      value.outbound_subscriptions.length().to_string() +
      "}"
    ConfigInvalid(issues) => {
      let values : Array[String] = []
      for issue in issues {
        values.push(
          "{\"code\":" +
          json_string(issue.code) +
          ",\"location\":" +
          json_string(issue.location) +
          ",\"message\":" +
          json_string(issue.message) +
          "}",
        )
      }
      "{\"valid\":false,\"issues\":[" + values.join(",") + "]}"
    }
  }
}
