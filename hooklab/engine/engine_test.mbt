///|
test "idempotency rejects duplicate until TTL expires" {
  let store = MemoryIdempotencyStore::new(ttl_seconds=10L)
  assert_true(store.check_and_record("delivery-1", 100L) == Accepted)
  assert_true(store.check_and_record("delivery-1", 105L) == Duplicate)
  assert_true(store.check_and_record("delivery-1", 110L) == Accepted)
  assert_eq(store.size(), 1)
}

///|
test "idempotency namespaces isolate providers and tenants" {
  let store = MemoryIdempotencyStore::new(ttl_seconds=10L)
  assert_true(
    store.check_and_record_scoped("github", "delivery-1", 100L) == Accepted,
  )
  assert_true(
    store.check_and_record_scoped("stripe", "delivery-1", 100L) == Accepted,
  )
  assert_true(
    store.check_and_record_scoped("github", "delivery-1", 101L) == Duplicate,
  )
  assert_true(
    store.check_and_record_scoped("", "delivery-1", 101L) == InvalidKey,
  )
  assert_true(store.check_and_record_scoped("github", "  ", 101L) == InvalidKey)
  assert_eq(store.size(), 2)
}

///|
test "length-prefixed scopes cannot collide" {
  assert_true(
    scoped_idempotency_key("a", "bc") != scoped_idempotency_key("ab", "c"),
  )
}

///|
test "retry schedule is capped and deterministic" {
  let policy : RetryPolicy = {
    max_attempts: 5,
    initial_delay_ms: 1000L,
    multiplier: 2L,
    max_delay_ms: 3000L,
  }
  let steps = retry_schedule(policy, 10000L)
  assert_eq(steps.length(), 5)
  assert_true(
    steps.map(fn(step) { step.delay_ms }) == [0L, 1000L, 2000L, 3000L, 3000L],
  )
  assert_true(steps[4].scheduled_at_ms == 19000L)
}

///|
test "delivery stops after final retry" {
  let policy = RetryPolicy::default()
  assert_true(
    decide_delivery(policy, 1, Retryable(503, "unavailable")) ==
    RetryAfter(1000L),
  )
  assert_true(
    decide_delivery(policy, 5, TransportFailure("timeout")) is DeadLetter(_),
  )
  assert_true(decide_delivery(policy, 1, Delivered(204)) == Success)
}

///|
test "Retry-After extends backoff and respects policy cap" {
  let policy = RetryPolicy::default()
  assert_true(
    decide_delivery_with_retry_after(
      policy,
      1,
      Retryable(429, "rate limited"),
      Some("15"),
    ) ==
    RetryAfter(15000L),
  )
  assert_true(
    decide_delivery_with_retry_after(
      policy,
      1,
      Retryable(503, "maintenance"),
      Some("3600"),
    ) ==
    RetryAfter(60000L),
  )
}

///|
test "malformed Retry-After falls back and final attempt stays dead letter" {
  let policy = RetryPolicy::default()
  assert_true(
    decide_delivery_with_retry_after(
      policy,
      2,
      TransportFailure("timeout"),
      Some("not-a-delay"),
    ) ==
    RetryAfter(2000L),
  )
  assert_true(
    decide_delivery_with_retry_after(
      policy,
      5,
      Retryable(429, "rate limited"),
      Some("15"),
    )
    is DeadLetter(_),
  )
  assert_true(parse_retry_after_seconds("-1") is None)
}

///|
test "router matches nested scalar values" {
  let rules : Array[RouteRule] = [
    {
      name: "push-main",
      path: "$.ref",
      operator: Equals,
      expected: "refs/heads/main",
      target: "https://deploy.test",
    },
    {
      name: "paid",
      path: "data.status",
      operator: Equals,
      expected: "paid",
      target: "https://billing.test",
    },
  ]
  let matches = route(
    "{\"ref\":\"refs/heads/main\",\"data\":{\"status\":\"paid\"}}", rules,
  )
  assert_eq(matches.length(), 2)
  assert_eq(matches[0].rule_name, "push-main")
}

///|
test "router addresses array items by numeric path segment" {
  let rules : Array[RouteRule] = [
    {
      name: "first-paid-item",
      path: "items.0.status",
      operator: Equals,
      expected: "paid",
      target: "queue://billing",
    },
    {
      name: "second-sku-prefix",
      path: "$.items.1.sku",
      operator: StartsWith,
      expected: "PRO-",
      target: "queue://provisioning",
    },
  ]
  let body = "{\"items\":[{\"status\":\"paid\"},{\"sku\":\"PRO-ANNUAL\"}]}"
  let matches = route(body, rules)
  assert_eq(matches.length(), 2)
  assert_eq(matches[1].rule_name, "second-sku-prefix")
}

///|
test "router supports suffix matching and rejects invalid array indexes" {
  let rules : Array[RouteRule] = [
    {
      name: "json-file",
      path: "files.0.name",
      operator: EndsWith,
      expected: ".json",
      target: "queue://json",
    },
    {
      name: "out-of-range",
      path: "files.9.name",
      operator: Exists,
      expected: "",
      target: "queue://invalid",
    },
    {
      name: "not-an-index",
      path: "files.first.name",
      operator: Exists,
      expected: "",
      target: "queue://invalid",
    },
  ]
  let matches = route("{\"files\":[{\"name\":\"event.json\"}]}", rules)
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].rule_name, "json-file")
}

///|
test "invalid JSON has no routes" {
  let rules : Array[RouteRule] = []
  assert_true(route("not-json", rules).is_empty())
}

///|
test "redaction is recursive and case insensitive" {
  let result = redact_json(
    "{\"token\":\"abc\",\"nested\":{\"Email\":\"a@example.com\",\"safe\":1}}",
  )
  assert_true(result.contains("[REDACTED]"))
  assert_false(result.contains("a@example.com"))
  assert_true(result.contains("\"safe\": 1"))
}

///|
test "fixture excludes secrets from headers and body" {
  let request : @core.WebhookRequest = {
    provider: @core.GenericHmac,
    headers: [
      @core.header("Authorization", "Bearer secret"),
      @core.header("X-Webhook-Id", "id-1"),
    ],
    body: "{\"password\":\"secret\",\"name\":\"ok\"}",
    received_at: 50L,
  }
  let fixture = capture_fixture(request, "user.updated")
  assert_true(fixture.headers[0].value == "[REDACTED]")
  assert_false(fixture.body.contains("secret"))
  assert_true(fixture.delivery_id == Some("id-1"))
}
