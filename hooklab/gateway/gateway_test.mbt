///|
fn generic_request(id : String, body : String) -> @core.WebhookRequest {
  let timestamp = "100"
  let secret = "gateway-secret"
  let signature = "sha256=" +
    @crypto.hmac_sha256_hex(secret, timestamp + "." + body)
  {
    provider: @core.GenericHmac,
    headers: [
      @core.header("x-webhook-signature", signature),
      @core.header("x-webhook-timestamp", timestamp),
      @core.header("x-webhook-id", id),
      @core.header("x-webhook-event", "invoice.paid"),
    ],
    body,
    received_at: 100L,
  }
}

///|
test "gateway verifies, persists, routes, and delivers an event" {
  let gateway = Gateway::new([
    {
      name: "paid",
      path: "status",
      operator: @engine.Equals,
      expected: "paid",
      target: "https://billing.test/webhook",
    },
  ])
  let request = generic_request(
    "evt-provider-1", "{\"status\":\"paid\",\"token\":\"must-not-leak\"}",
  )
  match gateway.accept(request, ["old-secret", "gateway-secret"], 100000L) {
    Accepted(event, deliveries) => {
      assert_eq(event.id, "generic-hmac:evt-provider-1")
      assert_false(event.redacted_body.contains("must-not-leak"))
      assert_eq(deliveries.length(), 1)
    }
    Rejected(failure) => fail(failure.message)
  }
  assert_eq(gateway.stats().events, 1)
  let claimed = gateway.claim_due(100000L)
  assert_eq(claimed.length(), 1)
  assert_true(
    gateway.record_outcome(claimed[0].id, @engine.Delivered(202), 100010L) ==
    @delivery.Updated,
  )
  assert_eq(gateway.stats().delivered, 1)
}

///|
test "gateway rejects duplicate before creating side effects" {
  let gateway = Gateway::new([])
  let request = generic_request("same-id", "{\"status\":\"paid\"}")
  assert_true(gateway.accept(request, ["gateway-secret"], 0L) is Accepted(_, _))
  match gateway.accept(request, ["gateway-secret"], 1L) {
    Rejected(failure) => assert_true(failure.code == @core.ReplayDetected)
    Accepted(_, _) => fail("expected duplicate rejection")
  }
  assert_eq(gateway.stats().events, 1)
}

///|
test "invalid signatures never pollute event or idempotency state" {
  let gateway = Gateway::new([])
  let mut request = generic_request("bad-first", "{\"status\":\"paid\"}")
  request = {
    ..request,
    headers: [
      @core.header("x-webhook-signature", "sha256=" + "0".repeat(64)),
      @core.header("x-webhook-timestamp", "100"),
      @core.header("x-webhook-id", "bad-first"),
    ],
  }
  assert_true(gateway.accept(request, ["gateway-secret"], 0L) is Rejected(_))
  assert_eq(gateway.stats().events, 0)
}

///|
test "prepare is side effect free and can be committed later" {
  let gateway = Gateway::new([
    {
      name: "paid",
      path: "status",
      operator: @engine.Equals,
      expected: "paid",
      target: "https://billing.test/webhook",
    },
  ])
  let request = generic_request("prepared-1", "{\"status\":\"paid\"}")
  match gateway.prepare(request, ["gateway-secret"], 100000L) {
    Prepared(event, deliveries) => {
      assert_eq(event.id, "generic-hmac:prepared-1")
      assert_eq(deliveries.length(), 1)
    }
    PreparationRejected(failure) => fail(failure.message)
  }
  assert_eq(gateway.stats().events, 0)
  assert_eq(gateway.stats().pending, 0)
  assert_true(
    gateway.accept(request, ["gateway-secret"], 100000L) is Accepted(_, _),
  )
  assert_eq(gateway.stats().events, 1)
}
