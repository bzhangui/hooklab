///|
fn application() -> Application {
  { id: "orders", publish_token_env: "HOOKLAB_PUBLISH_ORDERS", enabled: true, }
}

///|
fn endpoint(id : String, url : String) -> Endpoint {
  {
    id,
    url,
    signing_secret_env: "HOOKLAB_SIGNING_SECRET",
    key_id: "key-v1",
    enabled: true,
  }
}

///|
test "exact and wildcard subscriptions each create independent work" {
  let subscriptions : Array[Subscription] = [
    {
      id: "exact",
      application_id: "orders",
      endpoint_id: "receiver",
      event_types: ["order.created"],
      enabled: true,
    },
    {
      id: "all-orders",
      application_id: "orders",
      endpoint_id: "receiver",
      event_types: ["*"],
      enabled: true,
    },
    {
      id: "other-app",
      application_id: "billing",
      endpoint_id: "receiver",
      event_types: ["*"],
      enabled: true,
    },
  ]
  match
    plan_publication(
      application(),
      [endpoint("receiver", "https://example.test/webhook")],
      subscriptions,
      "order.created",
      "request-42",
      "{\"order\":42}",
    ) {
    Planned(plan) => {
      assert_eq(plan.deliveries.length(), 2)
      assert_eq(plan.deliveries[0].subscription_id, "exact")
      assert_eq(plan.deliveries[1].subscription_id, "all-orders")
      assert_not_eq(plan.deliveries[0].id, plan.deliveries[1].id)
    }
    PlanRejected(_) => fail("unexpected publication rejection")
  }
}

///|
test "publication identifiers are deterministic and content fingerprint is not" {
  let first = publication_event_id("orders", "request-42")
  let second = publication_event_id("orders", "request-42")
  assert_eq(first, second)
  assert_true(first.has_prefix("publish:"))
  assert_eq(
    publication_fingerprint("orders", "order.created", "{\"value\":1}"),
    publication_fingerprint("orders", "order.created", "{\"value\":1}"),
  )
  assert_not_eq(
    publication_fingerprint("orders", "order.created", "{\"value\":1}"),
    publication_fingerprint("orders", "order.created", "{\"value\":2}"),
  )
}

///|
test "disabled endpoint suppresses work and broken reference is rejected" {
  let disabled : Endpoint = {
    ..endpoint("receiver", "https://example.test/webhook"),
    enabled: false,
  }
  let subscription : Subscription = {
    id: "orders",
    application_id: "orders",
    endpoint_id: "receiver",
    event_types: ["*"],
    enabled: true,
  }
  match
    plan_publication(
      application(),
      [disabled],
      [subscription],
      "order.created",
      "request-42",
      "{}",
    ) {
    Planned(plan) => assert_eq(plan.deliveries.length(), 0)
    PlanRejected(_) => fail("unexpected publication rejection")
  }
  match
    plan_publication(
      application(),
      [],
      [subscription],
      "order.created",
      "request-42",
      "{}",
    ) {
    PlanRejected(UnknownEndpoint(id)) => assert_eq(id, "receiver")
    _ => fail("missing endpoint must be rejected")
  }
}

///|
test "publisher tokens use bearer authentication" {
  assert_true(publish_token_matches("secret-token", "secret-token"))
  assert_false(publish_token_matches("secret-token", "secret-taken"))
  assert_false(publish_token_matches("", ""))
  assert_true(authorize_bearer("secret-token", "Bearer secret-token"))
  assert_false(authorize_bearer("secret-token", "Basic secret-token"))
  assert_false(authorize_bearer("secret-token", "Bearer secret-taken"))
}

///|
test "delivery header tokens reject whitespace and metacharacters" {
  assert_true(delivery_token_valid("order.created/v2"))
  assert_false(delivery_token_valid("order created"))
  assert_false(delivery_token_valid("order*"))
  match
    plan_publication(application(), [], [], "order created", "request-42", "{}") {
    PlanRejected(InvalidEventType) => ()
    _ => fail("unsafe event type must be rejected before persistence")
  }
}

///|
test "outbound signature has a stable canonical vector" {
  let message = signing_message(
    1700000000L, "delivery:demo", "publish:demo", "order.created", "{\"message\":\"hello\\nHookLab\"}",
  )
  inspect(
    message,
    content=(
      #|v1
      #|1700000000
      #|delivery:demo
      #|publish:demo
      #|order.created
      #|{"message":"hello\nHookLab"}
    ),
  )
  let signature = sign_delivery(
    "test-secret", 1700000000L, "delivery:demo", "publish:demo", "order.created",
    "{\"message\":\"hello\\nHookLab\"}",
  )
  inspect(
    signature,
    content="v1=978a6161dd2b90f1a4576d6982447e4e45c0fea27ec2a414fcf3c487549172e0",
  )
  assert_true(
    verify_delivery_signature(
      ["previous-secret", "test-secret"],
      signature,
      1700000000L,
      "delivery:demo",
      "publish:demo",
      "order.created",
      "{\"message\":\"hello\\nHookLab\"}",
    ),
  )
  assert_false(
    verify_delivery_signature(
      ["test-secret"],
      signature,
      1700000000L,
      "delivery:demo",
      "publish:demo",
      "order.created",
      "{\"message\":\"tampered\"}",
    ),
  )
  let empty_secret_signature = sign_delivery(
    "", 1700000000L, "delivery:demo", "publish:demo", "order.created", "{}",
  )
  assert_false(
    verify_delivery_signature(
      [""],
      empty_secret_signature,
      1700000000L,
      "delivery:demo",
      "publish:demo",
      "order.created",
      "{}",
    ),
  )
}
