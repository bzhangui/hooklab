///|
/// Successful output of the safe processing pipeline. The body is redacted for
/// logs and reports; `event.body` remains the verified raw body for delivery.
pub(all) struct ProcessedEvent {
  event : @core.VerifiedEvent
  routes : Array[@engine.RouteMatch]
  redacted_body : String
} derive(Eq, Debug)

///|
pub(all) enum ProcessingResult {
  Processed(ProcessedEvent)
  Rejected(@core.VerificationFailure)
} derive(Eq, Debug)

///|
/// Runs the security-sensitive stages in their required order: signature and
/// freshness verification, idempotency, routing, then diagnostic redaction.
pub fn process(
  request : @core.WebhookRequest,
  secret : String,
  store : @engine.MemoryIdempotencyStore,
  routes : Array[@engine.RouteRule],
  verification_policy? : @core.VerificationPolicy = @core.VerificationPolicy::secure_default(),
  redaction_policy? : @engine.RedactionPolicy = @engine.RedactionPolicy::secure_default(),
) -> ProcessingResult {
  match @providers.verify(request, secret, policy=verification_policy) {
    @core.Rejected(failure) => Rejected(failure)
    @core.Verified(event) =>
      match event.delivery_id {
        Some(id) =>
          match
            store.check_and_record_scoped(
              @core.provider_name(event.provider),
              id,
              request.received_at,
            ) {
            @engine.Duplicate =>
              Rejected({
                code: @core.ReplayDetected,
                stage: @core.Idempotency,
                message: "This delivery identifier was already processed.",
                suggestion: "Acknowledge the duplicate without repeating side effects.",
              })
            @engine.InvalidKey =>
              Rejected({
                code: @core.MissingDeliveryId,
                stage: @core.Idempotency,
                message: "The delivery identifier is empty.",
                suggestion: "Forward a non-empty provider delivery identifier.",
              })
            @engine.Accepted =>
              Processed({
                event,
                routes: @engine.route(event.body, routes),
                redacted_body: @engine.redact_json(
                  event.body,
                  policy=redaction_policy,
                ),
              })
          }
        None =>
          Processed({
            event,
            routes: @engine.route(event.body, routes),
            redacted_body: @engine.redact_json(
              event.body,
              policy=redaction_policy,
            ),
          })
      }
  }
}
