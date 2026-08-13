///|
/// Portable replay fixture. Secrets are deliberately excluded.
pub(all) struct ReplayFixture {
  version : Int
  provider : @core.Provider
  event_type : String
  delivery_id : String?
  headers : Array[@core.Header]
  body : String
  captured_at : Int64
} derive(Eq, Debug)

///|
pub fn capture_fixture(
  request : @core.WebhookRequest,
  event_type : String,
  policy? : RedactionPolicy = RedactionPolicy::secure_default(),
) -> ReplayFixture {
  {
    version: 1,
    provider: request.provider,
    event_type,
    delivery_id: match request.provider {
      @core.GitHub => @core.find_header(request.headers, "x-github-delivery")
      @core.Stripe =>
        @core.find_header(request.headers, "x-hooklab-delivery-id")
      @core.Feishu => @core.find_header(request.headers, "x-lark-request-nonce")
      @core.GenericHmac => @core.find_header(request.headers, "x-webhook-id")
    },
    headers: redact_headers(request.headers, policy~),
    body: redact_json(request.body, policy~),
    captured_at: request.received_at,
  }
}

///|
/// Creates a replay request with a new reception time. Signature headers are
/// retained as evidence but a real replay destination should normally bypass
/// provider verification or re-sign with an explicit test secret.
pub fn replay_request(
  fixture : ReplayFixture,
  now : Int64,
) -> @core.WebhookRequest {
  {
    provider: fixture.provider,
    headers: fixture.headers,
    body: fixture.body,
    received_at: now,
  }
}
