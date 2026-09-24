///|
fn platform_field(root : Json, name : String) -> Json? {
  match root {
    Object(values) => values.get_from_string(name)
    _ => None
  }
}

///|
fn platform_text(root : Json, name : String) -> String? {
  match platform_field(root, name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
/// The PostgreSQL adapter supplies only subscriptions already filtered by
/// tenant, application, enabled state and event type. MoonBit still owns the
/// publication plan and validates endpoint references before persistence.
fn platform_plan(
  application_id : String,
  event_type : String,
  idempotency_key : String,
  payload : String,
  catalog_json : String,
) -> String {
  let catalog = try @json.parse(catalog_json) catch {
    _ => return "{\"accepted\":false}"
  } noraise {
    value => value
  }
  guard catalog is Array(items) else { return "{\"accepted\":false}" }
  let endpoints : Array[@outbound.Endpoint] = []
  let subscriptions : Array[@outbound.Subscription] = []
  for item in items {
    guard platform_text(item, "subscription_id") is Some(subscription_id) else {
      return "{\"accepted\":false}"
    }
    guard platform_text(item, "endpoint_id") is Some(endpoint_id) else {
      return "{\"accepted\":false}"
    }
    guard platform_text(item, "url") is Some(url) else {
      return "{\"accepted\":false}"
    }
    guard platform_text(item, "key_id") is Some(key_id) else {
      return "{\"accepted\":false}"
    }
    endpoints.push({
      id: endpoint_id,
      url,
      signing_secret_env: "",
      key_id,
      enabled: true,
    })
    subscriptions.push({
      id: subscription_id,
      application_id,
      endpoint_id,
      event_types: [event_type],
      enabled: true,
    })
  }
  let application : @outbound.Application = {
    id: application_id,
    publish_token_env: "",
    enabled: true,
  }
  match
    @outbound.plan_publication(
      application, endpoints, subscriptions, event_type, idempotency_key, payload,
    ) {
    @outbound.PlanRejected(_) => "{\"accepted\":false}"
    @outbound.Planned(plan) => {
      let ids : Array[String] = []
      for delivery in plan.deliveries {
        ids.push(gateway_json_string(delivery.subscription_id))
      }
      "{\"accepted\":true,\"subscriptions\":[" + ids.join(",") + "]}"
    }
  }
}

///|
fn platform_validate(
  payload : String,
  media_type : String,
  event_type : String,
  schema_json : String,
  require_cloudevents : Bool,
) -> String {
  let issues = @contract.validate_event_json(
    payload, media_type, event_type, schema_json, require_cloudevents,
  )
  let result : Array[String] = []
  for issue in issues {
    result.push(
      "{\"code\":" +
      gateway_json_string(issue.code) +
      ",\"location\":" +
      gateway_json_string(issue.location) +
      "}",
    )
  }
  "{\"valid\":" +
  issues.is_empty().to_string() +
  ",\"issues\":[" +
  result.join(",") +
  "]}"
}

///|
fn serve_platform(args : Array[String]) -> Unit {
  let port = if args.length() > 1 {
    try @string.parse_int(args[1]) catch {
      _ => 0
    } noraise {
      value => value
    }
  } else {
    8787
  }
  if port < 1 || port > 65535 {
    println("Port must be between 1 and 65535.")
    set_exit_code(1)
    return
  }
  run_platform_runtime(
    port,
    platform_plan,
    fn(secret, timestamp, delivery_id, event_id, event_type, payload) {
      @outbound.sign_delivery(
        secret, timestamp, delivery_id, event_id, event_type, payload,
      )
    },
    gateway_decision_json,
    platform_validate,
  )
}
