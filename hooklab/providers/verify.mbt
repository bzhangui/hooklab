///|
fn parse_timestamp(value : String) -> Int64? {
  try @string.parse_int64(@core.trim_ascii(value)) catch {
    _ => None
  } noraise {
    timestamp => Some(timestamp)
  }
}

///|
fn is_hex_digest(value : String, length : Int) -> Bool {
  if value.length() != length {
    return false
  }
  for c in value {
    let lowered = if c >= 'A' && c <= 'F' {
      (c.to_int() + 32).unsafe_to_char()
    } else {
      c
    }
    if !(lowered >= '0' && lowered <= '9') &&
      !(lowered >= 'a' && lowered <= 'f') {
      return false
    }
  }
  true
}

///|
fn check_freshness(
  timestamp : Int64?,
  received_at : Int64,
  policy : @core.VerificationPolicy,
) -> @core.VerificationResult? {
  guard timestamp is Some(value) else { return None }
  if value > received_at + policy.reject_future_seconds {
    Some(
      @core.rejection(
        @core.TimestampInFuture,
        @core.Freshness,
        "The webhook timestamp is later than the allowed clock skew.",
        "Synchronize system clocks and verify the timestamp header source.",
      ),
    )
  } else if received_at - value > policy.tolerance_seconds {
    Some(
      @core.rejection(
        @core.TimestampExpired,
        @core.Freshness,
        "The webhook timestamp is outside the accepted freshness window.",
        "Use a fresh delivery or explicitly widen the policy tolerance.",
      ),
    )
  } else {
    None
  }
}

///|
fn event_type(request : @core.WebhookRequest) -> String {
  match request.provider {
    @core.GitHub =>
      @core.find_header(request.headers, "x-github-event").unwrap_or("unknown")
    @core.Stripe => "stripe.event"
    @core.Feishu =>
      @core.find_header(request.headers, "x-lark-event-type").unwrap_or(
        "feishu.event",
      )
    @core.GenericHmac =>
      @core.find_header(request.headers, "x-webhook-event").unwrap_or(
        "webhook.event",
      )
  }
}

///|
fn delivery_id(request : @core.WebhookRequest) -> String? {
  match request.provider {
    @core.GitHub => @core.find_header(request.headers, "x-github-delivery")
    @core.Stripe => @core.find_header(request.headers, "x-hooklab-delivery-id")
    @core.Feishu => @core.find_header(request.headers, "x-lark-request-nonce")
    @core.GenericHmac => @core.find_header(request.headers, "x-webhook-id")
  }
}

///|
fn finish_verified(
  request : @core.WebhookRequest,
  timestamp : Int64?,
  policy : @core.VerificationPolicy,
) -> @core.VerificationResult {
  let id = delivery_id(request)
  if policy.require_delivery_id && id is None {
    @core.rejection(
      @core.MissingDeliveryId,
      @core.Input,
      "The policy requires a delivery identifier, but none was supplied.",
      "Forward the provider delivery ID or set x-webhook-id for generic events.",
    )
  } else {
    @core.Verified({
      provider: request.provider,
      event_type: event_type(request),
      delivery_id: id,
      timestamp,
      body: request.body,
    })
  }
}

///|
fn verify_github(
  request : @core.WebhookRequest,
  secret : String,
  policy : @core.VerificationPolicy,
) -> @core.VerificationResult {
  guard @core.find_header(request.headers, "x-hub-signature-256") is Some(raw) else {
    return @core.rejection(
      @core.MissingSignature,
      @core.Signature,
      "GitHub signature header x-hub-signature-256 is missing.",
      "Configure the GitHub webhook secret and forward the original headers.",
    )
  }
  let signature = @core.trim_ascii(raw)
  guard signature.has_prefix("sha256=") &&
    is_hex_digest(signature[7:].to_owned(), 64) else {
    return @core.rejection(
      @core.InvalidSignatureFormat,
      @core.Signature,
      "GitHub signatures must use the sha256=<64 hex characters> form.",
      "Do not transform the x-hub-signature-256 header before verification.",
    )
  }
  let expected = "sha256=" + @crypto.hmac_sha256_hex(secret, request.body)
  if !@crypto.constant_time_equal(@core.ascii_lower(signature), expected) {
    @core.rejection(
      @core.SignatureMismatch,
      @core.Signature,
      "The GitHub HMAC-SHA256 signature does not match the raw request body.",
      "Verify the secret and ensure verification uses the unmodified raw body.",
    )
  } else {
    finish_verified(request, None, policy)
  }
}

///|
priv struct StripeSignature {
  timestamp : Int64?
  signatures : Array[String]
}

///|
fn parse_stripe_header(value : String) -> StripeSignature {
  let mut timestamp : Int64? = None
  let signatures : Array[String] = []
  for segment in value.split(",") {
    match segment.to_owned().split_once("=") {
      Some((key, val)) => {
        let key = @core.trim_ascii(key.to_owned())
        let val = @core.trim_ascii(val.to_owned())
        if key == "t" {
          timestamp = parse_timestamp(val)
        } else if key == "v1" && is_hex_digest(val, 64) {
          signatures.push(@core.ascii_lower(val))
        }
      }
      None => ()
    }
  }
  { timestamp, signatures }
}

///|
fn verify_stripe(
  request : @core.WebhookRequest,
  secret : String,
  policy : @core.VerificationPolicy,
) -> @core.VerificationResult {
  guard @core.find_header(request.headers, "stripe-signature") is Some(raw) else {
    return @core.rejection(
      @core.MissingSignature,
      @core.Signature,
      "Stripe-Signature header is missing.",
      "Forward the original Stripe-Signature header.",
    )
  }
  let parsed = parse_stripe_header(raw)
  guard parsed.timestamp is Some(timestamp) else {
    return @core.rejection(
      @core.MissingTimestamp,
      @core.Signature,
      "Stripe-Signature does not contain a valid t field.",
      "Use the complete Stripe-Signature header without editing it.",
    )
  }
  guard !parsed.signatures.is_empty() else {
    return @core.rejection(
      @core.InvalidSignatureFormat,
      @core.Signature,
      "Stripe-Signature does not contain a v1 signature.",
      "Use a current Stripe endpoint secret and a v1 signature.",
    )
  }
  let expected = @crypto.hmac_sha256_hex(
    secret,
    timestamp.to_string() + "." + request.body,
  )
  let mut matches = false
  for candidate in parsed.signatures {
    // Do not stop on a match: compare every v1 value to keep work independent
    // of the matching candidate position during secret rotation.
    matches = @crypto.constant_time_equal(candidate, expected) || matches
  }
  if !matches {
    @core.rejection(
      @core.SignatureMismatch,
      @core.Signature,
      "No Stripe v1 signature matches the signed timestamp and raw body.",
      "Check the endpoint secret and preserve the raw request body.",
    )
  } else {
    match check_freshness(Some(timestamp), request.received_at, policy) {
      Some(failure) => failure
      None => finish_verified(request, Some(timestamp), policy)
    }
  }
}

///|
fn verify_feishu(
  request : @core.WebhookRequest,
  encrypt_key : String,
  policy : @core.VerificationPolicy,
) -> @core.VerificationResult {
  guard @core.find_header(request.headers, "x-lark-signature")
    is Some(signature) else {
    return @core.rejection(
      @core.MissingSignature,
      @core.Signature,
      "Feishu signature header x-lark-signature is missing.",
      "Enable request signing and forward all x-lark-* headers.",
    )
  }
  guard is_hex_digest(@core.trim_ascii(signature), 64) else {
    return @core.rejection(
      @core.InvalidSignatureFormat,
      @core.Signature,
      "Feishu signatures must contain exactly 64 hexadecimal characters.",
      "Forward x-lark-signature without modification.",
    )
  }
  guard @core.find_header(request.headers, "x-lark-request-timestamp")
    is Some(raw_timestamp) else {
    return @core.rejection(
      @core.MissingTimestamp,
      @core.Signature,
      "Feishu request timestamp is missing or invalid.",
      "Forward x-lark-request-timestamp as an integer Unix timestamp.",
    )
  }
  guard parse_timestamp(raw_timestamp) is Some(timestamp) else {
    return @core.rejection(
      @core.MissingTimestamp,
      @core.Signature,
      "Feishu request timestamp is missing or invalid.",
      "Forward x-lark-request-timestamp as an integer Unix timestamp.",
    )
  }
  guard @core.find_header(request.headers, "x-lark-request-nonce")
    is Some(nonce) else {
    return @core.rejection(
      @core.InvalidSignatureFormat,
      @core.Signature,
      "Feishu request nonce is missing.",
      "Forward x-lark-request-nonce without modification.",
    )
  }
  let expected = @crypto.sha256_hex(
    raw_timestamp + nonce + encrypt_key + request.body,
  )
  if !@crypto.constant_time_equal(
      @core.ascii_lower(@core.trim_ascii(signature)),
      expected,
    ) {
    @core.rejection(
      @core.SignatureMismatch,
      @core.Signature,
      "The Feishu SHA-256 signature does not match.",
      "Check the encrypt key and preserve timestamp, nonce, and raw body.",
    )
  } else {
    match check_freshness(Some(timestamp), request.received_at, policy) {
      Some(failure) => failure
      None => finish_verified(request, Some(timestamp), policy)
    }
  }
}

///|
fn verify_generic(
  request : @core.WebhookRequest,
  secret : String,
  policy : @core.VerificationPolicy,
) -> @core.VerificationResult {
  guard @core.find_header(request.headers, "x-webhook-signature") is Some(raw) else {
    return @core.rejection(
      @core.MissingSignature,
      @core.Signature,
      "Generic signature header x-webhook-signature is missing.",
      "Send sha256=<hex> in x-webhook-signature.",
    )
  }
  let signature = @core.ascii_lower(@core.trim_ascii(raw))
  guard signature.has_prefix("sha256=") &&
    is_hex_digest(signature[7:].to_owned(), 64) else {
    return @core.rejection(
      @core.InvalidSignatureFormat,
      @core.Signature,
      "Generic signatures must use the sha256=<64 hex characters> form.",
      "Send a complete HMAC-SHA256 signature.",
    )
  }
  let raw_timestamp = @core.find_header(request.headers, "x-webhook-timestamp")
  let timestamp = match raw_timestamp {
    Some(value) => parse_timestamp(value)
    None => None
  }
  if raw_timestamp is Some(_) && timestamp is None {
    return @core.rejection(
      @core.MissingTimestamp,
      @core.Signature,
      "The generic webhook timestamp is present but is not a Unix integer.",
      "Send x-webhook-timestamp as integer seconds or omit it from both signature and request.",
    )
  }
  let signed_payload = match timestamp {
    Some(value) => value.to_string() + "." + request.body
    None => request.body
  }
  let expected = "sha256=" + @crypto.hmac_sha256_hex(secret, signed_payload)
  if !@crypto.constant_time_equal(signature, expected) {
    @core.rejection(
      @core.SignatureMismatch,
      @core.Signature,
      "The generic HMAC-SHA256 signature does not match.",
      "Sign '<timestamp>.<body>' when a timestamp is present, otherwise sign the raw body.",
    )
  } else {
    match check_freshness(timestamp, request.received_at, policy) {
      Some(failure) => failure
      None => finish_verified(request, timestamp, policy)
    }
  }
}

///|
/// Verifies a request with provider-specific signing rules and a shared
/// freshness policy. The secret means webhook secret for GitHub/Stripe/generic
/// and encrypt key for Feishu.
pub fn verify(
  request : @core.WebhookRequest,
  secret : String,
  policy? : @core.VerificationPolicy = @core.VerificationPolicy::secure_default(),
) -> @core.VerificationResult {
  match request.provider {
    @core.GitHub => verify_github(request, secret, policy)
    @core.Stripe => verify_stripe(request, secret, policy)
    @core.Feishu => verify_feishu(request, secret, policy)
    @core.GenericHmac => verify_generic(request, secret, policy)
  }
}

///|
/// Verifies against every configured secret to support zero-downtime secret
/// rotation. All candidates are evaluated even after a match so the amount of
/// verification work does not reveal which key in the ring is active.
pub fn verify_with_secrets(
  request : @core.WebhookRequest,
  secrets : Array[String],
  policy? : @core.VerificationPolicy = @core.VerificationPolicy::secure_default(),
) -> @core.VerificationResult {
  guard !secrets.is_empty() else {
    return @core.rejection(
      @core.InvalidPayload,
      @core.Input,
      "At least one webhook secret is required for verification.",
      "Configure the active secret and any previous secret retained during rotation.",
    )
  }
  let mut matched : @core.VerifiedEvent? = None
  let mut first_failure : @core.VerificationFailure? = None
  for secret in secrets {
    match verify(request, secret, policy~) {
      @core.Verified(event) => matched = Some(event)
      @core.Rejected(failure) =>
        if first_failure is None {
          first_failure = Some(failure)
        }
    }
  }
  match matched {
    Some(event) => @core.Verified(event)
    None => @core.Rejected(first_failure.unwrap())
  }
}
