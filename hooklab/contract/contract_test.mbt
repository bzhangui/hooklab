///|
test "contract reports all missing requirements" {
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [@core.header("x-github-delivery", "d-1")],
    body: "{\"repository\":{\"name\":\"demo\"}}",
    received_at: 10L,
  }
  let contract : WebhookContract = {
    name: "github-push",
    provider: @core.GitHub,
    event_type: Some("push"),
    required_headers: ["x-github-delivery", "x-hub-signature-256"],
    required_paths: ["repository.name", "ref"],
    max_body_chars: 4096,
  }
  match validate(request, "issues", contract) {
    Invalid(issues) => assert_eq(issues.length(), 3)
    Valid => fail("expected contract issues")
  }
}

///|
test "contract accepts nested arrays and case-insensitive headers" {
  let request : @core.WebhookRequest = {
    provider: @core.GenericHmac,
    headers: [@core.header("X-Webhook-ID", "d-1")],
    body: "{\"items\":[{\"sku\":\"A\"}]}",
    received_at: 10L,
  }
  let contract : WebhookContract = {
    name: "order",
    provider: @core.GenericHmac,
    event_type: None,
    required_headers: ["x-webhook-id"],
    required_paths: ["items.0.sku"],
    max_body_chars: 1024,
  }
  assert_true(validate(request, "order.created", contract) == Valid)
}
