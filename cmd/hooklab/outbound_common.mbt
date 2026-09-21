///|
fn outbound_application(
  config : @config.GatewayConfig,
  id : String,
) -> @outbound.Application? {
  for application in config.outbound_applications {
    if application.id == id {
      return Some(application)
    }
  }
  None
}

///|
fn outbound_endpoint(
  config : @config.GatewayConfig,
  id : String,
) -> @outbound.Endpoint? {
  for endpoint in config.outbound_endpoints {
    if endpoint.id == id {
      return Some(endpoint)
    }
  }
  None
}

///|
fn publication_error_code(error : @outbound.PublicationError) -> String {
  match error {
    @outbound.InvalidApplication => "invalid_application"
    @outbound.ApplicationDisabled => "application_disabled"
    @outbound.InvalidEventType => "invalid_event_type"
    @outbound.InvalidIdempotencyKey => "invalid_idempotency_key"
    @outbound.InvalidPayload => "invalid_payload"
    @outbound.InvalidSubscription(_) => "invalid_subscription"
    @outbound.UnknownEndpoint(_) => "unknown_endpoint"
  }
}

///|
fn outbound_publish_json(
  config : @config.GatewayConfig,
  application_id : String,
  authorization : String,
  idempotency_key : String,
  event_type : String,
  payload : String,
) -> String {
  guard outbound_application(config, application_id) is Some(application) else {
    return "{\"accepted\":false,\"status\":404,\"code\":\"application_not_found\"}"
  }
  let expected_token = read_environment(application.publish_token_env).unwrap_or(
    "",
  )
  if !@outbound.authorize_bearer(expected_token, authorization) {
    return "{\"accepted\":false,\"status\":401,\"code\":\"unauthorized\"}"
  }
  match
    @outbound.plan_publication(
      application,
      config.outbound_endpoints,
      config.outbound_subscriptions,
      event_type,
      idempotency_key,
      payload,
    ) {
    @outbound.PlanRejected(error) =>
      "{\"accepted\":false,\"status\":422,\"code\":" +
      gateway_json_string(publication_error_code(error)) +
      "}"
    @outbound.Planned(plan) => {
      let deliveries : Array[String] = []
      for delivery in plan.deliveries {
        deliveries.push(
          "{\"id\":" +
          gateway_json_string(delivery.id) +
          ",\"subscription_id\":" +
          gateway_json_string(delivery.subscription_id) +
          ",\"endpoint_id\":" +
          gateway_json_string(delivery.endpoint_id) +
          ",\"target\":" +
          gateway_json_string(delivery.target) +
          ",\"key_id\":" +
          gateway_json_string(delivery.key_id) +
          ",\"payload\":" +
          gateway_json_string(delivery.payload) +
          "}",
        )
      }
      "{\"accepted\":true,\"status\":202,\"event_id\":" +
      gateway_json_string(plan.event_id) +
      ",\"application_id\":" +
      gateway_json_string(plan.application_id) +
      ",\"event_type\":" +
      gateway_json_string(plan.event_type) +
      ",\"idempotency_key\":" +
      gateway_json_string(plan.idempotency_key) +
      ",\"fingerprint\":" +
      gateway_json_string(plan.fingerprint) +
      ",\"redacted_body\":" +
      gateway_json_string(@engine.redact_json(plan.payload)) +
      ",\"deliveries\":[" +
      deliveries.join(",") +
      "]}"
    }
  }
}

///|
fn outbound_signature(
  config : @config.GatewayConfig,
  endpoint_id : String,
  target : String,
  key_id : String,
  timestamp : Int64,
  delivery_id : String,
  event_id : String,
  event_type : String,
  payload : String,
) -> String {
  guard outbound_endpoint(config, endpoint_id) is Some(endpoint) else {
    return ""
  }
  if endpoint.url != target || endpoint.key_id != key_id {
    return ""
  }
  let secret = read_environment(endpoint.signing_secret_env).unwrap_or("")
  if secret.is_empty() {
    ""
  } else {
    @outbound.sign_delivery(
      secret, timestamp, delivery_id, event_id, event_type, payload,
    )
  }
}

///|
fn outbound_catalog_json(config : @config.GatewayConfig) -> String {
  let applications : Array[String] = []
  for application in config.outbound_applications {
    applications.push(
      "{\"id\":" +
      gateway_json_string(application.id) +
      ",\"enabled\":" +
      application.enabled.to_string() +
      "}",
    )
  }
  let endpoints : Array[String] = []
  for endpoint in config.outbound_endpoints {
    endpoints.push(
      "{\"id\":" +
      gateway_json_string(endpoint.id) +
      ",\"url\":" +
      gateway_json_string(endpoint.url) +
      ",\"keyId\":" +
      gateway_json_string(endpoint.key_id) +
      ",\"enabled\":" +
      endpoint.enabled.to_string() +
      "}",
    )
  }
  let subscriptions : Array[String] = []
  for subscription in config.outbound_subscriptions {
    let types : Array[String] = []
    for event_type in subscription.event_types {
      types.push(gateway_json_string(event_type))
    }
    subscriptions.push(
      "{\"id\":" +
      gateway_json_string(subscription.id) +
      ",\"applicationId\":" +
      gateway_json_string(subscription.application_id) +
      ",\"endpointId\":" +
      gateway_json_string(subscription.endpoint_id) +
      ",\"eventTypes\":[" +
      types.join(",") +
      "],\"enabled\":" +
      subscription.enabled.to_string() +
      "}",
    )
  }
  "{\"applications\":[" +
  applications.join(",") +
  "],\"endpoints\":[" +
  endpoints.join(",") +
  "],\"subscriptions\":[" +
  subscriptions.join(",") +
  "]}"
}

///|
fn validate_outbound_environment(config : @config.GatewayConfig) -> String? {
  for application in config.outbound_applications {
    if application.enabled &&
      read_environment(application.publish_token_env).unwrap_or("").is_empty() {
      return Some(
        "No publisher token was found in environment variable " +
        application.publish_token_env +
        ".",
      )
    }
  }
  for endpoint in config.outbound_endpoints {
    if endpoint.enabled &&
      read_environment(endpoint.signing_secret_env).unwrap_or("").is_empty() {
      return Some(
        "No signing secret was found in environment variable " +
        endpoint.signing_secret_env +
        ".",
      )
    }
  }
  None
}
