///|
pub(all) enum IngressResult {
  Accepted(@event.EventRecord, Array[@delivery.Delivery])
  Rejected(@core.VerificationFailure)
} derive(Eq, Debug)

///|
/// A side-effect-free ingress plan. Runtime adapters can verify, route, and
/// transform first, then atomically commit the event, idempotency key, and all
/// deliveries in their own storage transaction.
pub(all) enum PreparationResult {
  Prepared(@event.EventRecord, Array[@delivery.Delivery])
  PreparationRejected(@core.VerificationFailure)
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
  transforms : Array[@transform.RouteTransform]
}

///|
pub fn Gateway::new(
  routes : Array[@engine.RouteRule],
  idempotency_ttl_seconds? : Int64 = 86400L,
) -> Gateway {
  Gateway::new_with_transforms(routes, [], idempotency_ttl_seconds~)
}

///|
pub fn Gateway::new_with_transforms(
  routes : Array[@engine.RouteRule],
  transforms : Array[@transform.RouteTransform],
  idempotency_ttl_seconds? : Int64 = 86400L,
) -> Gateway {
  {
    idempotency: @engine.MemoryIdempotencyStore::new(
      ttl_seconds=idempotency_ttl_seconds,
    ),
    event_store: @event.EventStore::new(),
    delivery_queue: @delivery.DeliveryQueue::new(),
    routes,
    transforms,
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
fn Gateway::transform_for_route(
  self : Gateway,
  route_name : String,
) -> @transform.RouteTransform? {
  for plan in self.transforms {
    if plan.route_name == route_name {
      return Some(plan)
    }
  }
  None
}

///|
fn transformation_failure(
  route_name : String,
  failure : @transform.TransformFailure,
) -> @core.VerificationFailure {
  {
    code: @core.InvalidPayload,
    stage: @core.Routing,
    message: "Route " +
    route_name +
    " rejected its transformation: " +
    @transform.failure_code_name(failure.code) +
    ". " +
    failure.message,
    suggestion: "Adjust the route transformation or its explicit execution budgets before retrying.",
  }
}

///|
/// Verifies and plans an ingress request without mutating gateway state.
/// Durable adapters should call this method and commit the returned plan in a
/// single storage transaction.
pub fn Gateway::prepare(
  self : Gateway,
  request : @core.WebhookRequest,
  secrets : Array[String],
  now_ms : Int64,
  verification_policy? : @core.VerificationPolicy = @core.VerificationPolicy::secure_default(),
  redaction_policy? : @engine.RedactionPolicy = @engine.RedactionPolicy::secure_default(),
) -> PreparationResult {
  let verified = match
    @providers.verify_with_secrets(request, secrets, policy=verification_policy) {
    @core.Verified(event) => event
    @core.Rejected(failure) => return PreparationRejected(failure)
  }
  let routed : Array[(@engine.RouteMatch, String?)] = []
  for matched in @engine.route(verified.body, self.routes) {
    let payload : String? = match self.transform_for_route(matched.rule_name) {
      None => None
      Some(plan) =>
        match @transform.apply(verified.body, plan.operations, plan.budget) {
          @transform.Transformed(body, _) => Some(body)
          @transform.TransformRejected(failure) =>
            return PreparationRejected(
              transformation_failure(matched.rule_name, failure),
            )
        }
    }
    routed.push((matched, payload))
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
  let created : Array[@delivery.Delivery] = []
  let planned = @delivery.DeliveryQueue::new()
  for item in routed {
    let matched = item.0
    let payload = item.1
    let id = delivery_identifier(event_id, matched.target)
    if planned.enqueue(id, event_id, matched.target, now_ms, payload~) ==
      @delivery.Enqueued {
      match planned.get(id) {
        Some(item) => created.push(item)
        None => ()
      }
    }
  }
  Prepared(record, created)
}

///|
/// Accepts a request into the in-memory event-delivery domain. Verification
/// and every matched route transformation complete before idempotency is
/// recorded. Durable runtime adapters should prefer `prepare` and atomically
/// commit its result in their storage layer.
pub fn Gateway::accept(
  self : Gateway,
  request : @core.WebhookRequest,
  secrets : Array[String],
  now_ms : Int64,
  verification_policy? : @core.VerificationPolicy = @core.VerificationPolicy::secure_default(),
  redaction_policy? : @engine.RedactionPolicy = @engine.RedactionPolicy::secure_default(),
) -> IngressResult {
  let (record, deliveries) = match
    self.prepare(
      request,
      secrets,
      now_ms,
      verification_policy~,
      redaction_policy~,
    ) {
    Prepared(record, deliveries) => (record, deliveries)
    PreparationRejected(failure) => return Rejected(failure)
  }
  match record.delivery_id {
    Some(id) =>
      match
        self.idempotency.check_and_record_scoped(
          @core.provider_name(record.provider),
          id,
          record.received_at,
        ) {
        @engine.Accepted => ()
        @engine.Duplicate | @engine.InvalidKey =>
          return Rejected(duplicate_failure())
      }
    None => ()
  }
  guard self.event_store.append(record) == @event.Appended else {
    return Rejected(duplicate_failure())
  }
  let created : Array[@delivery.Delivery] = []
  for delivery in deliveries {
    if self.delivery_queue.enqueue(
        delivery.id,
        delivery.event_id,
        delivery.target,
        delivery.created_at_ms,
        payload=delivery.payload,
        ordering_key=delivery.ordering_key,
      ) ==
      @delivery.Enqueued {
      match self.delivery_queue.get(delivery.id) {
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
