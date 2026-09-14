///|
test "Stripe extracts official event id and type after verification" {
  let body = "{\"id\":\"evt_123\",\"type\":\"checkout.session.completed\"}"
  let timestamp = 1700000000L
  let signature = @crypto.hmac_sha256_hex(
    "whsec_test",
    timestamp.to_string() + "." + body,
  )
  let request : @core.WebhookRequest = {
    provider: @core.Stripe,
    headers: [
      @core.header(
        "Stripe-Signature",
        "t=" + timestamp.to_string() + ",v1=" + signature,
      ),
    ],
    body,
    received_at: timestamp + 1L,
  }
  guard verify(request, "whsec_test") is @core.Verified(event) else {
    fail("expected Stripe event to verify")
  }
  assert_true(event.delivery_id == Some("evt_123"))
  assert_eq(event.event_type, "checkout.session.completed")
}

///|
test "Feishu extracts v2 event type from signed payload" {
  let timestamp = "1700000000"
  let nonce = "nonce-1"
  let body = "{\"schema\":\"2.0\",\"header\":{\"event_type\":\"im.message.receive_v1\"}}"
  let signature = @crypto.sha256_hex(timestamp + nonce + "encrypt-key" + body)
  let request : @core.WebhookRequest = {
    provider: @core.Feishu,
    headers: [
      @core.header("X-Lark-Signature", signature),
      @core.header("X-Lark-Request-Timestamp", timestamp),
      @core.header("X-Lark-Request-Nonce", nonce),
    ],
    body,
    received_at: 1700000001L,
  }
  guard verify(request, "encrypt-key") is @core.Verified(event) else {
    fail("expected Feishu event to verify")
  }
  assert_eq(event.event_type, "im.message.receive_v1")
}
