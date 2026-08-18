///|
test "GitHub official-style signature verifies" {
  let body = "Hello, World!"
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [
      @core.header(
        "X-Hub-Signature-256",
        "sha256=" + @crypto.hmac_sha256_hex("It's a Secret to Everybody", body),
      ),
      @core.header("X-GitHub-Event", "push"),
      @core.header("X-GitHub-Delivery", "delivery-1"),
    ],
    body,
    received_at: 1000L,
  }
  guard verify(request, "It's a Secret to Everybody") is @core.Verified(event) else {
    fail("expected verification success")
  }
  assert_eq(event.event_type, "push")
  assert_true(event.delivery_id == Some("delivery-1"))
}

///|
test "GitHub official published verification vector" {
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [
      @core.header(
        "X-Hub-Signature-256", "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17",
      ),
    ],
    body: "Hello, World!",
    received_at: 1000L,
  }
  assert_true(
    verify(request, "It's a Secret to Everybody") is @core.Verified(_),
  )
}

///|
test "GitHub rejects non-hex signature before comparison" {
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [
      @core.header(
        "x-hub-signature-256", "sha256=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
      ),
    ],
    body: "payload",
    received_at: 1000L,
  }
  guard verify(request, "secret") is @core.Rejected(failure) else {
    fail("expected format rejection")
  }
  assert_true(failure.code == @core.InvalidSignatureFormat)
}

///|
test "GitHub rejects a modified body" {
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [
      @core.header(
        "x-hub-signature-256",
        "sha256=" + @crypto.hmac_sha256_hex("secret", "original"),
      ),
    ],
    body: "modified",
    received_at: 1000L,
  }
  guard verify(request, "secret") is @core.Rejected(failure) else {
    fail("expected rejection")
  }
  assert_true(failure.code == @core.SignatureMismatch)
}

///|
test "Stripe accepts any matching v1 during rotation" {
  let body = "{\"id\":\"evt_1\"}"
  let timestamp = 1700000000L
  let valid = @crypto.hmac_sha256_hex(
    "whsec_test",
    timestamp.to_string() + "." + body,
  )
  let request : @core.WebhookRequest = {
    provider: @core.Stripe,
    headers: [
      @core.header("Stripe-Signature", "t=1700000000,v1=deadbeef,v1=" + valid),
    ],
    body,
    received_at: timestamp + 10L,
  }
  assert_true(verify(request, "whsec_test") is @core.Verified(_))
}

///|
test "Stripe rejects stale signed event" {
  let body = "{}"
  let valid = @crypto.hmac_sha256_hex("secret", "1000." + body)
  let request : @core.WebhookRequest = {
    provider: @core.Stripe,
    headers: [@core.header("Stripe-Signature", "t=1000,v1=" + valid)],
    body,
    received_at: 1400L,
  }
  guard verify(request, "secret") is @core.Rejected(failure) else {
    fail("expected stale rejection")
  }
  assert_true(failure.code == @core.TimestampExpired)
}

///|
test "Stripe rejects a valid signature from the future" {
  let body = "{}"
  let valid = @crypto.hmac_sha256_hex("secret", "1100." + body)
  let request : @core.WebhookRequest = {
    provider: @core.Stripe,
    headers: [@core.header("Stripe-Signature", "t=1100,v1=" + valid)],
    body,
    received_at: 1000L,
  }
  guard verify(request, "secret") is @core.Rejected(failure) else {
    fail("expected future rejection")
  }
  assert_true(failure.code == @core.TimestampInFuture)
}

///|
test "Feishu signing formula verifies" {
  let body = "{\"schema\":\"2.0\"}"
  let timestamp = "1700000000"
  let nonce = "abc123"
  let signature = @crypto.sha256_hex(timestamp + nonce + "encrypt-key" + body)
  let request : @core.WebhookRequest = {
    provider: @core.Feishu,
    headers: [
      @core.header("X-Lark-Signature", signature),
      @core.header("X-Lark-Request-Timestamp", timestamp),
      @core.header("X-Lark-Request-Nonce", nonce),
    ],
    body,
    received_at: 1700000010L,
  }
  assert_true(verify(request, "encrypt-key") is @core.Verified(_))
}

///|
test "generic signature includes timestamp when present" {
  let body = "{\"ok\":true}"
  let signature = @crypto.hmac_sha256_hex("secret", "2000." + body)
  let request : @core.WebhookRequest = {
    provider: @core.GenericHmac,
    headers: [
      @core.header("X-Webhook-Signature", "sha256=" + signature),
      @core.header("X-Webhook-Timestamp", "2000"),
      @core.header("X-Webhook-Id", "generic-1"),
    ],
    body,
    received_at: 2001L,
  }
  assert_true(verify(request, "secret") is @core.Verified(_))
}

///|
test "generic malformed timestamp cannot bypass freshness" {
  let body = "{}"
  let signature = @crypto.hmac_sha256_hex("secret", body)
  let request : @core.WebhookRequest = {
    provider: @core.GenericHmac,
    headers: [
      @core.header("X-Webhook-Signature", "sha256=" + signature),
      @core.header("X-Webhook-Timestamp", "not-a-time"),
    ],
    body,
    received_at: 2001L,
  }
  guard verify(request, "secret") is @core.Rejected(failure) else {
    fail("expected timestamp rejection")
  }
  assert_true(failure.code == @core.MissingTimestamp)
}

///|
test "secret ring accepts previous key during rotation" {
  let body = "{\"action\":\"rotated\"}"
  let signature = @crypto.hmac_sha256_hex("previous-secret", body)
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [
      @core.header("X-Hub-Signature-256", "sha256=" + signature),
      @core.header("X-GitHub-Delivery", "rotation-1"),
    ],
    body,
    received_at: 1000L,
  }
  assert_true(
    verify_with_secrets(request, [
      "current-secret", "previous-secret", "unrelated-secret",
    ])
    is @core.Verified(_),
  )
  assert_true(
    verify_with_secrets(request, ["current-secret", "unrelated-secret"])
    is @core.Rejected(_),
  )
}

///|
test "secret ring rejects empty configuration" {
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [],
    body: "{}",
    received_at: 1000L,
  }
  guard verify_with_secrets(request, []) is @core.Rejected(failure) else {
    fail("expected empty secret ring rejection")
  }
  assert_true(failure.code == @core.InvalidPayload)
}
