///|
pub(all) enum IngressResult {
  Accepted(@event.EventRecord, Array[@delivery.Delivery])
  Rejected(@core.VerificationFailure)
} derive(Eq, Debug)

///|
pub(all) struct GatewayStats {
  events : Int
  pending : Int
  scheduled : Int
  in_flight : Int
  delivered : Int
  dead_lettered : Int
  cancelled : Int
} derive(Eq, Debug)

///|
pub struct Gateway {
  idempotency : @engine.MemoryIdempotencyStore
  event_store : @event.EventStore
  delivery_queue : @delivery.DeliveryQueue
  routes : Array[@engine.RouteRule]
}

///|
pub fn Gateway::new(
  routes : Array[@engine.RouteRule],
  idempotency_ttl_seconds? : Int64 = 86400L,
) -> Gateway {
  {
    idempotency: @engine.MemoryIdempotencyStore::new(
      ttl_seconds=idempotency_ttl_seconds,
    ),
    event_store: @event.EventStore::new(),
    delivery_queue: @delivery.DeliveryQueue::new(),
    routes,
  }
}

///|
fn event_identifier(event : @core.VerifiedEvent, received_at : Int64) -> String {
  match event.delivery_id {
    Some(id) => @core.provider_name(event.provider) + ":" + id
    None => {
      let digest = @crypto.sha256_hex(
        @core.provider_name(event.provider) +
        "\n" +
        event.event_type +
        "\n" +
        received_at.to_string() +
        "\n" +
        event.body,
      )
      @core.provider_name(event.provider) +
      ":generated:" +
      digest[0:24].to_owned()
    }
  }
}

///|
fn delivery_identifier(event_id : String, target : String) -> String {
  let digest = @crypto.sha256_hex(event_id + "\n" + target)
  "delivery:" + digest[0:24].to_owned()
}

///|
fn duplicate_failure() -> @core.VerificationFailure {
  {
    code: @core.ReplayDetected,
    stage: @core.Idempotency,
    message: "This provider delivery identifier has already been accepted.",
    suggestion: "Acknowledge the duplicate without repeating downstream side effects.",
  }
}

///|
/// Accepts a request into the event-delivery domain. Verification happens
/// before idempotency state is touched, and only verified events are persisted
/// or expanded into delivery work.
pub fn Gateway::accept(
  self : Gateway,
  request : @core.WebhookRequest,
  secrets : Array[String],
  now_ms : Int64,
  verification_policy? : @core.VerificationPolicy = @core.VerificationPolicy::secure_default(),
  redaction_policy? : @engine.RedactionPolicy = @engine.RedactionPolicy::secure_default(),
) -> IngressResult {
  let verified = match
    @providers.verify_with_secrets(request, secrets, policy=verification_policy) {
    @core.Verified(event) => event
    @core.Rejected(failure) => return Rejected(failure)
  }
  match verified.delivery_id {
    Some(id) =>
      match
        self.idempotency.check_and_record_scoped(
          @core.provider_name(verified.provider),
          id,
          request.received_at,
        ) {
        @engine.Accepted => ()
        @engine.Duplicate | @engine.InvalidKey =>
          return Rejected(duplicate_failure())
      }
    None => ()
  }
  let event_id = event_identifier(verified, request.received_at)
  let record : @event.EventRecord = {
    id: event_id,
    provider: verified.provider,
    event_type: verified.event_type,
    delivery_id: verified.delivery_id,
    body: verified.body,
    redacted_body: @engine.redact_json(verified.body, policy=redaction_policy),
    received_at: request.received_at,
  }
  guard self.event_store.append(record) == @event.Appended else {
    return Rejected(duplicate_failure())
  }
  let created : Array[@delivery.Delivery] = []
  for matched in @engine.route(verified.body, self.routes) {
    let id = delivery_identifier(event_id, matched.target)
    if self.delivery_queue.enqueue(id, event_id, matched.target, now_ms) ==
      @delivery.Enqueued {
      match self.delivery_queue.get(id) {
        Some(item) => created.push(item)
        None => ()
      }
    }
  }
  Accepted(record, created)
}

///|
pub fn Gateway::events(self : Gateway) -> Array[@event.EventRecord] {
  self.event_store.all()
}

///|
pub fn Gateway::deliveries(self : Gateway) -> Array[@delivery.Delivery] {
  self.delivery_queue.all()
}

///|
pub fn Gateway::claim_due(
  self : Gateway,
  now_ms : Int64,
  limit? : Int = 1,
) -> Array[@delivery.Delivery] {
  self.delivery_queue.claim_due(now_ms, limit~)
}

///|
pub fn Gateway::record_outcome(
  self : Gateway,
  id : String,
  outcome : @engine.AttemptOutcome,
  now_ms : Int64,
  retry_after? : String? = None,
  policy? : @engine.RetryPolicy = @engine.RetryPolicy::default(),
) -> @delivery.UpdateResult {
  self.delivery_queue.record_outcome(id, outcome, now_ms, retry_after~, policy~)
}

///|
pub fn Gateway::replay_dead_letter(
  self : Gateway,
  id : String,
  now_ms : Int64,
) -> @delivery.UpdateResult {
  self.delivery_queue.replay_dead_letter(id, now_ms)
}

///|
pub fn Gateway::stats(self : Gateway) -> GatewayStats {
  let mut pending = 0
  let mut scheduled = 0
  let mut in_flight = 0
  let mut delivered = 0
  let mut dead_lettered = 0
  let mut cancelled = 0
  for item in self.delivery_queue.all() {
    match item.state {
      @delivery.Pending => pending = pending + 1
      @delivery.Scheduled => scheduled = scheduled + 1
      @delivery.InFlight => in_flight = in_flight + 1
      @delivery.Delivered => delivered = delivered + 1
      @delivery.DeadLettered => dead_lettered = dead_lettered + 1
      @delivery.Cancelled => cancelled = cancelled + 1
    }
  }
  {
    events: self.event_store.size(),
    pending,
    scheduled,
    in_flight,
    delivered,
    dead_lettered,
    cancelled,
  }
}
