///|
/// A supported webhook signature convention.
pub(all) enum Provider {
  GitHub
  Stripe
  Feishu
  GenericHmac
} derive(Eq, Debug)

///|
/// Stable machine-readable failure codes. Callers should branch on these
/// values instead of parsing human-readable messages.
pub(all) enum FailureCode {
  MissingSignature
  MissingTimestamp
  InvalidSignatureFormat
  SignatureMismatch
  TimestampExpired
  TimestampInFuture
  ReplayDetected
  MissingDeliveryId
  InvalidPayload
  UnsupportedProvider
} derive(Eq, Debug)

///|
/// The stage at which webhook processing stopped.
pub(all) enum Stage {
  Input
  Signature
  Freshness
  Idempotency
  Routing
  Delivery
  Complete
} derive(Eq, Debug)

///|
pub(all) struct Header {
  name : String
  value : String
} derive(Eq, Debug)

///|
pub fn header(name : String, value : String) -> Header {
  { name, value }
}

///|
/// Immutable input to the verification pipeline. `body` must be the exact raw
/// request bytes interpreted as UTF-8 text; parsing and re-serializing JSON
/// before verification changes the signed bytes.
pub(all) struct WebhookRequest {
  provider : Provider
  headers : Array[Header]
  body : String
  received_at : Int64
} derive(Eq, Debug)

///|
pub(all) struct VerificationPolicy {
  tolerance_seconds : Int64
  reject_future_seconds : Int64
  require_delivery_id : Bool
} derive(Eq, Debug)

///|
pub fn VerificationPolicy::secure_default() -> VerificationPolicy {
  {
    tolerance_seconds: 300L,
    reject_future_seconds: 30L,
    require_delivery_id: false,
  }
}

///|
pub(all) struct VerifiedEvent {
  provider : Provider
  event_type : String
  delivery_id : String?
  timestamp : Int64?
  body : String
} derive(Eq, Debug)

///|
pub(all) struct VerificationFailure {
  code : FailureCode
  stage : Stage
  message : String
  suggestion : String
} derive(Eq, Debug)

///|
pub(all) enum VerificationResult {
  Verified(VerifiedEvent)
  Rejected(VerificationFailure)
} derive(Eq, Debug)

///|
pub fn rejection(
  code : FailureCode,
  stage : Stage,
  message : String,
  suggestion : String,
) -> VerificationResult {
  Rejected({ code, stage, message, suggestion })
}

///|
fn ascii_lower_char(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
pub fn ascii_lower(value : String) -> String {
  let out = StringBuilder::new()
  for c in value {
    out.write_char(ascii_lower_char(c))
  }
  out.to_string()
}

///|
/// Header lookup is ASCII case-insensitive as required by HTTP.
pub fn find_header(headers : Array[Header], name : String) -> String? {
  let wanted = ascii_lower(name)
  for item in headers {
    if ascii_lower(item.name) == wanted {
      return Some(item.value)
    }
  }
  None
}

///|
pub fn trim_ascii(value : String) -> String {
  let chars = value.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end && is_ascii_space(chars[start]) {
    start = start + 1
  }
  while end > start && is_ascii_space(chars[end - 1]) {
    end = end - 1
  }
  let out = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
/// Stable lowercase provider identifier for reports and command-line output.
pub fn provider_name(provider : Provider) -> String {
  match provider {
    GitHub => "github"
    Stripe => "stripe"
    Feishu => "feishu"
    GenericHmac => "generic-hmac"
  }
}

///|
/// Stable failure identifier intended for automation and JSON output.
pub fn failure_code_name(code : FailureCode) -> String {
  match code {
    MissingSignature => "missing_signature"
    MissingTimestamp => "missing_timestamp"
    InvalidSignatureFormat => "invalid_signature_format"
    SignatureMismatch => "signature_mismatch"
    TimestampExpired => "timestamp_expired"
    TimestampInFuture => "timestamp_in_future"
    ReplayDetected => "replay_detected"
    MissingDeliveryId => "missing_delivery_id"
    InvalidPayload => "invalid_payload"
    UnsupportedProvider => "unsupported_provider"
  }
}

///|
/// Stable processing-stage identifier intended for diagnosis output.
pub fn stage_name(stage : Stage) -> String {
  match stage {
    Input => "input"
    Signature => "signature"
    Freshness => "freshness"
    Idempotency => "idempotency"
    Routing => "routing"
    Delivery => "delivery"
    Complete => "complete"
  }
}

///|
fn is_ascii_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}
