///|
/// Persistent delivery lifecycle. Transport and storage adapters may live on
/// any backend; the state transitions stay deterministic and testable here.
pub(all) enum DeliveryState {
  Pending
  Scheduled
  InFlight
  Delivered
  DeadLettered
  Cancelled
} derive(Eq, Debug)

///|
pub(all) struct Delivery {
  id : String
  event_id : String
  target : String
  ordering_key : String?
  attempt : Int
  state : DeliveryState
  next_attempt_at_ms : Int64
  last_status : Int?
  last_error : String?
  created_at_ms : Int64
  updated_at_ms : Int64
} derive(Eq, Debug)

///|
pub(all) enum EnqueueResult {
  Enqueued
  DuplicateDelivery
  InvalidDelivery
} derive(Eq, Debug)

///|
pub(all) enum UpdateResult {
  Updated
  NotFound
  InvalidTransition
} derive(Eq, Debug)

///|
pub struct DeliveryQueue {
  deliveries : Array[Delivery]
}

///|
pub fn DeliveryQueue::new() -> DeliveryQueue {
  { deliveries: [], }
}

///|
pub fn DeliveryQueue::size(self : DeliveryQueue) -> Int {
  self.deliveries.length()
}

///|
pub fn DeliveryQueue::all(self : DeliveryQueue) -> Array[Delivery] {
  self.deliveries.copy()
}

///|
fn DeliveryQueue::index_of(self : DeliveryQueue, id : String) -> Int? {
  for i = 0; i < self.deliveries.length(); i = i + 1 {
    if self.deliveries[i].id == id {
      return Some(i)
    }
  }
  None
}

///|
pub fn DeliveryQueue::get(self : DeliveryQueue, id : String) -> Delivery? {
  match self.index_of(id) {
    Some(index) => Some(self.deliveries[index])
    None => None
  }
}

///|
pub fn DeliveryQueue::enqueue(
  self : DeliveryQueue,
  id : String,
  event_id : String,
  target : String,
  now_ms : Int64,
  ordering_key? : String? = None,
) -> EnqueueResult {
  if id.trim().is_empty() ||
    event_id.trim().is_empty() ||
    target.trim().is_empty() {
    return InvalidDelivery
  }
  if self.index_of(id) is Some(_) {
    return DuplicateDelivery
  }
  self.deliveries.push({
    id,
    event_id,
    target,
    ordering_key,
    attempt: 0,
    state: Pending,
    next_attempt_at_ms: now_ms,
    last_status: None,
    last_error: None,
    created_at_ms: now_ms,
    updated_at_ms: now_ms,
  })
  Enqueued
}

///|
fn DeliveryQueue::ordering_key_busy(self : DeliveryQueue, key : String) -> Bool {
  self.deliveries.any(fn(item) {
    item.ordering_key == Some(key) && item.state == InFlight
  })
}

///|
/// Claims due work in insertion order. Only one in-flight delivery is allowed
/// for the same ordering key, which preserves per-stream ordering while still
/// allowing unrelated streams to progress concurrently.
pub fn DeliveryQueue::claim_due(
  self : DeliveryQueue,
  now_ms : Int64,
  limit? : Int = 1,
) -> Array[Delivery] {
  if limit <= 0 {
    return []
  }
  let claimed : Array[Delivery] = []
  for i = 0; i < self.deliveries.length(); i = i + 1 {
    if claimed.length() >= limit {
      break
    }
    let item = self.deliveries[i]
    let due = (item.state == Pending || item.state == Scheduled) &&
      item.next_attempt_at_ms <= now_ms
    let blocked = match item.ordering_key {
      Some(key) => self.ordering_key_busy(key)
      None => false
    }
    if due && !blocked {
      let updated = {
        ..item,
        attempt: item.attempt + 1,
        state: InFlight,
        updated_at_ms: now_ms,
      }
      self.deliveries[i] = updated
      claimed.push(updated)
    }
  }
  claimed
}

///|
pub fn DeliveryQueue::record_outcome(
  self : DeliveryQueue,
  id : String,
  outcome : @engine.AttemptOutcome,
  now_ms : Int64,
  retry_after? : String? = None,
  policy? : @engine.RetryPolicy = @engine.RetryPolicy::default(),
) -> UpdateResult {
  guard self.index_of(id) is Some(index) else { return NotFound }
  let item = self.deliveries[index]
  guard item.state == InFlight else { return InvalidTransition }
  let (status, error) = match outcome {
    @engine.Delivered(code) => (Some(code), None)
    @engine.Retryable(code, reason) => (Some(code), Some(reason))
    @engine.Permanent(code, reason) => (Some(code), Some(reason))
    @engine.TransportFailure(reason) => (None, Some(reason))
  }
  let updated = match
    @engine.decide_delivery_with_retry_after(
      policy,
      item.attempt,
      outcome,
      retry_after,
    ) {
    @engine.Success =>
      {
        ..item,
        state: Delivered,
        last_status: status,
        last_error: None,
        updated_at_ms: now_ms,
      }
    @engine.RetryAfter(delay) =>
      {
        ..item,
        state: Scheduled,
        next_attempt_at_ms: now_ms + delay,
        last_status: status,
        last_error: error,
        updated_at_ms: now_ms,
      }
    @engine.DeadLetter(reason) =>
      {
        ..item,
        state: DeadLettered,
        last_status: status,
        last_error: Some(reason),
        updated_at_ms: now_ms,
      }
  }
  self.deliveries[index] = updated
  Updated
}

///|
pub fn DeliveryQueue::replay_dead_letter(
  self : DeliveryQueue,
  id : String,
  now_ms : Int64,
) -> UpdateResult {
  guard self.index_of(id) is Some(index) else { return NotFound }
  let item = self.deliveries[index]
  guard item.state == DeadLettered else { return InvalidTransition }
  self.deliveries[index] = {
    ..item,
    attempt: 0,
    state: Pending,
    next_attempt_at_ms: now_ms,
    last_status: None,
    last_error: None,
    updated_at_ms: now_ms,
  }
  Updated
}

///|
pub fn DeliveryQueue::cancel(
  self : DeliveryQueue,
  id : String,
  now_ms : Int64,
) -> UpdateResult {
  guard self.index_of(id) is Some(index) else { return NotFound }
  let item = self.deliveries[index]
  guard item.state == Pending || item.state == Scheduled else {
    return InvalidTransition
  }
  self.deliveries[index] = { ..item, state: Cancelled, updated_at_ms: now_ms, }
  Updated
}

///|
pub fn delivery_state_name(state : DeliveryState) -> String {
  match state {
    Pending => "pending"
    Scheduled => "scheduled"
    InFlight => "in_flight"
    Delivered => "delivered"
    DeadLettered => "dead_lettered"
    Cancelled => "cancelled"
  }
}
