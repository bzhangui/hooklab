///|
test "pipeline verifies routes redacts and rejects duplicate" {
  let body = "{\"action\":\"opened\",\"password\":\"do-not-log\"}"
  let secret = "pipeline-secret"
  let signature = "sha256=bd612e5fbbd92937d403cceea337fc61cc50db008a6c19c424654d5c801618d7"
  let request : @core.WebhookRequest = {
    provider: @core.GitHub,
    headers: [
      @core.header("x-hub-signature-256", signature),
      @core.header("x-github-event", "issues"),
      @core.header("x-github-delivery", "delivery-1"),
    ],
    body,
    received_at: 1000L,
  }
  let rules : Array[@engine.RouteRule] = [
    {
      name: "opened-issues",
      path: "action",
      operator: @engine.Equals,
      expected: "opened",
      target: "https://worker.example/issues",
    },
  ]
  let store = @engine.MemoryIdempotencyStore::new()
  match process(request, secret, store, rules) {
    Processed(output) => {
      inspect(output.routes.length(), content="1")
      inspect(output.redacted_body.contains("do-not-log"), content="false")
      inspect(output.redacted_body.contains("[REDACTED]"), content="true")
    }
    Rejected(_) => inspect("rejected", content="processed")
  }
  match process(request, secret, store, rules) {
    Rejected(failure) =>
      inspect(failure.code == @core.ReplayDetected, content="true")
    Processed(_) => inspect("accepted duplicate", content="rejected duplicate")
  }
}
