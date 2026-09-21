///|
/// A publisher namespace. The environment-variable name is configuration
/// metadata only; the token value is supplied separately at runtime.
pub(all) struct Application {
  id : String
  publish_token_env : String
  enabled : Bool
} derive(Eq, Debug)

///|
/// A subscriber endpoint. Secret values are never part of this model.
pub(all) struct Endpoint {
  id : String
  url : String
  signing_secret_env : String
  key_id : String
  enabled : Bool
} derive(Eq, Debug)

///|
/// A subscription is an independent delivery relationship. Two matching
/// subscriptions intentionally produce two deliveries even if they reference
/// the same endpoint.
pub(all) struct Subscription {
  id : String
  application_id : String
  endpoint_id : String
  event_types : Array[String]
  enabled : Bool
} derive(Eq, Debug)

///|
pub(all) struct PlannedDelivery {
  id : String
  subscription_id : String
  endpoint_id : String
  target : String
  key_id : String
  event_type : String
  payload : String
} derive(Eq, Debug)

///|
/// A deterministic publication plan. `fingerprint` lets a transactional
/// adapter reject reuse of an idempotency key with different content.
pub(all) struct PublicationPlan {
  event_id : String
  application_id : String
  event_type : String
  idempotency_key : String
  fingerprint : String
  payload : String
  deliveries : Array[PlannedDelivery]
} derive(Eq, Debug)

///|
pub(all) enum PublicationError {
  InvalidApplication
  ApplicationDisabled
  InvalidEventType
  InvalidIdempotencyKey
  InvalidPayload
  InvalidSubscription(String)
  UnknownEndpoint(String)
} derive(Eq, Debug)

///|
pub(all) enum PlanResult {
  Planned(PublicationPlan)
  PlanRejected(PublicationError)
} derive(Eq, Debug)

///|
/// Validates values that are emitted in HookLab delivery headers. Keeping the
/// alphabet explicit prevents control characters or ambiguous whitespace from
/// turning an accepted publication into an undeliverable HTTP request.
pub fn delivery_token_valid(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  for c in value {
    let accepted = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '.' ||
      c == '_' ||
      c == '-' ||
      c == ':' ||
      c == '/'
    if !accepted {
      return false
    }
  }
  true
}

///|
pub fn publication_event_id(
  application_id : String,
  idempotency_key : String,
) -> String {
  let digest = @crypto.sha256_hex(application_id + "\n" + idempotency_key)
  "publish:" + digest[0:24].to_owned()
}

///|
pub fn publication_fingerprint(
  application_id : String,
  event_type : String,
  payload : String,
) -> String {
  @crypto.sha256_hex(application_id + "\n" + event_type + "\n" + payload)
}

///|
pub fn publication_delivery_id(
  event_id : String,
  subscription_id : String,
  endpoint_id : String,
) -> String {
  let digest = @crypto.sha256_hex(
    event_id + "\n" + subscription_id + "\n" + endpoint_id,
  )
  "delivery:" + digest[0:24].to_owned()
}

///|
pub fn subscription_matches(
  subscription : Subscription,
  application_id : String,
  event_type : String,
) -> Bool {
  if !subscription.enabled || subscription.application_id != application_id {
    return false
  }
  for candidate in subscription.event_types {
    if candidate == "*" || candidate == event_type {
      return true
    }
  }
  false
}

///|
fn endpoint_by_id(endpoints : Array[Endpoint], id : String) -> Endpoint? {
  for endpoint in endpoints {
    if endpoint.id == id {
      return Some(endpoint)
    }
  }
  None
}

///|
/// Creates one delivery for every matching subscription. Configuration
/// validation should normally catch broken references, but this function also
/// rejects them so command and adapter callers cannot silently lose work.
pub fn plan_publication(
  application : Application,
  endpoints : Array[Endpoint],
  subscriptions : Array[Subscription],
  event_type : String,
  idempotency_key : String,
  payload : String,
) -> PlanResult {
  let application_id = @core.trim_ascii(application.id)
  if application_id.is_empty() {
    return PlanRejected(InvalidApplication)
  }
  if !application.enabled {
    return PlanRejected(ApplicationDisabled)
  }
  let event_type = @core.trim_ascii(event_type)
  if !delivery_token_valid(event_type) {
    return PlanRejected(InvalidEventType)
  }
  let idempotency_key = @core.trim_ascii(idempotency_key)
  if idempotency_key.is_empty() {
    return PlanRejected(InvalidIdempotencyKey)
  }
  if payload.is_empty() {
    return PlanRejected(InvalidPayload)
  }
  let event_id = publication_event_id(application_id, idempotency_key)
  let deliveries : Array[PlannedDelivery] = []
  for subscription in subscriptions {
    if subscription_matches(subscription, application_id, event_type) {
      let subscription_id = @core.trim_ascii(subscription.id)
      if subscription_id.is_empty() {
        return PlanRejected(InvalidSubscription(subscription.id))
      }
      guard endpoint_by_id(endpoints, subscription.endpoint_id)
        is Some(endpoint) else {
        return PlanRejected(UnknownEndpoint(subscription.endpoint_id))
      }
      if endpoint.enabled {
        deliveries.push({
          id: publication_delivery_id(event_id, subscription_id, endpoint.id),
          subscription_id,
          endpoint_id: endpoint.id,
          target: endpoint.url,
          key_id: endpoint.key_id,
          event_type,
          payload,
        })
      }
    }
  }
  Planned({
    event_id,
    application_id,
    event_type,
    idempotency_key,
    fingerprint: publication_fingerprint(application_id, event_type, payload),
    payload,
    deliveries,
  })
}

///|
/// Validates a raw publisher token without an early-return byte comparison.
/// Empty configured tokens are never accepted.
pub fn publish_token_matches(expected : String, provided : String) -> Bool {
  !expected.is_empty() && @crypto.constant_time_equal(expected, provided)
}

///|
/// Validates the HTTP `Authorization: Bearer ...` form used by the publication
/// API. Scheme parsing is separate from the constant-time token comparison.
pub fn authorize_bearer(expected : String, authorization : String) -> Bool {
  let value = @core.trim_ascii(authorization)
  guard value.has_prefix("Bearer ") else { return false }
  publish_token_matches(expected, value[7:].to_owned())
}

///|
/// Canonical data signed for every outbound attempt. The timestamp may change
/// between retries, while the event and delivery identifiers remain stable.
pub fn signing_message(
  timestamp : Int64,
  delivery_id : String,
  event_id : String,
  event_type : String,
  payload : String,
) -> String {
  "v1\n" +
  timestamp.to_string() +
  "\n" +
  delivery_id +
  "\n" +
  event_id +
  "\n" +
  event_type +
  "\n" +
  payload
}

///|
pub fn sign_delivery(
  secret : String,
  timestamp : Int64,
  delivery_id : String,
  event_id : String,
  event_type : String,
  payload : String,
) -> String {
  "v1=" +
  @crypto.hmac_sha256_hex(
    secret,
    signing_message(timestamp, delivery_id, event_id, event_type, payload),
  )
}

///|
fn is_lower_hex_digest(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for c in value {
    if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {
      return false
    }
  }
  true
}

///|
/// Verifies every non-empty configured secret so secret-rotation order does
/// not reveal which candidate matched. Empty secrets are never valid.
/// Timestamp freshness is intentionally a transport policy and remains the
/// caller's responsibility.
pub fn verify_delivery_signature(
  secrets : Array[String],
  signature : String,
  timestamp : Int64,
  delivery_id : String,
  event_id : String,
  event_type : String,
  payload : String,
) -> Bool {
  let signature = @core.trim_ascii(signature)
  guard signature.has_prefix("v1=") else { return false }
  let digest = signature[3:].to_owned()
  guard is_lower_hex_digest(digest) else { return false }
  let message = signing_message(
    timestamp, delivery_id, event_id, event_type, payload,
  )
  let mut matched = false
  for secret in secrets {
    if !secret.is_empty() {
      let expected = @crypto.hmac_sha256_hex(secret, message)
      let candidate_matches = @crypto.constant_time_equal(digest, expected)
      matched = candidate_matches || matched
    }
  }
  matched
}
