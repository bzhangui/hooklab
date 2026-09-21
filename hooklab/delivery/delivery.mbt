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
  payload : String?
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
/// A fenced lease returned to one worker. The monotonically increasing token
/// prevents a worker whose lease expired from overwriting a newer result.
pub(all) struct DeliveryClaim {
  delivery : Delivery
  owner : String
  token : Int64
  expires_at_ms : Int64
} derive(Eq, Debug)

///|
/// Result of an operation that must prove ownership of an active lease.
/// Lease-aware APIs use a separate result type so the legacy single-process
/// update API remains source compatible.
pub(all) enum LeaseUpdateResult {
  LeaseUpdated
  LeaseNotFound
  LeaseInvalidTransition
  LeaseStale
  LeaseExpired
  LeaseInvalid
} derive(Eq, Debug)

///|
struct DeliveryLease {
  delivery_id : String
  owner : String
  token : Int64
  expires_at_ms : Int64
}

///|
pub struct DeliveryQueue {
  deliveries : Array[Delivery]
  leases : Array[DeliveryLease]
  mut next_lease_token : Int64
}

///|
pub fn DeliveryQueue::new() -> DeliveryQueue {
  { deliveries: [], leases: [], next_lease_token: 1L, }
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
fn DeliveryQueue::lease_index_of(self : DeliveryQueue, id : String) -> Int? {
  for i = 0; i < self.leases.length(); i = i + 1 {
    if self.leases[i].delivery_id == id {
      return Some(i)
    }
  }
  None
}

///|
fn DeliveryQueue::active_lease(
  self : DeliveryQueue,
  id : String,
) -> DeliveryLease? {
  match self.lease_index_of(id) {
    Some(index) => {
      let lease = self.leases[index]
      if lease.owner.is_empty() {
        None
      } else {
        Some(lease)
      }
    }
    None => None
  }
}

///|
fn DeliveryQueue::set_lease(
  self : DeliveryQueue,
  lease : DeliveryLease,
) -> Unit {
  match self.lease_index_of(lease.delivery_id) {
    Some(index) => self.leases[index] = lease
    None => self.leases.push(lease)
  }
}

///|
fn DeliveryQueue::clear_lease(self : DeliveryQueue, id : String) -> Unit {
  match self.lease_index_of(id) {
    Some(index) =>
      self.leases[index] = {
        delivery_id: id,
        owner: "",
        token: 0L,
        expires_at_ms: 0L,
      }
    None => ()
  }
}

///|
pub fn DeliveryQueue::get(self : DeliveryQueue, id : String) -> Delivery? {
  match self.index_of(id) {
    Some(index) => Some(self.deliveries[index])
    None => None
  }
}

///|
/// Returns the current fenced claim, including an expired one that has not yet
/// been recovered. Mutations must still use the token-aware update methods.
pub fn DeliveryQueue::get_claim(
  self : DeliveryQueue,
  id : String,
) -> DeliveryClaim? {
  guard self.get(id) is Some(delivery) else { return None }
  match self.active_lease(id) {
    Some(lease) =>
      Some({
        delivery,
        owner: lease.owner,
        token: lease.token,
        expires_at_ms: lease.expires_at_ms,
      })
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
  payload? : String? = None,
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
    payload,
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
/// Moves expired leased work back to the scheduled state. Attempts are not
/// decremented: a process may have sent the request before losing its lease,
/// so the eventual retry remains an at-least-once delivery attempt.
pub fn DeliveryQueue::recover_expired_leases(
  self : DeliveryQueue,
  now_ms : Int64,
) -> Int {
  let mut recovered = 0
  for i = 0; i < self.deliveries.length(); i = i + 1 {
    let item = self.deliveries[i]
    if item.state == InFlight {
      match self.active_lease(item.id) {
        Some(lease) if lease.expires_at_ms <= now_ms => {
          self.deliveries[i] = {
            ..item,
            state: Scheduled,
            next_attempt_at_ms: now_ms,
            last_error: Some("delivery lease expired"),
            updated_at_ms: now_ms,
          }
          self.clear_lease(item.id)
          recovered = recovered + 1
        }
        _ => ()
      }
    }
  }
  recovered
}

///|
/// Claims due work for a named worker and attaches a fenced, expiring lease.
/// Expired leases are recovered before new work is selected. Tokens are never
/// reused within a queue instance.
pub fn DeliveryQueue::claim_due_with_lease(
  self : DeliveryQueue,
  worker_id : String,
  now_ms : Int64,
  lease_ms : Int64,
  limit? : Int = 1,
) -> Array[DeliveryClaim] {
  if worker_id.trim().is_empty() || lease_ms <= 0L || limit <= 0 {
    return []
  }
  ignore(self.recover_expired_leases(now_ms))
  let claimed : Array[DeliveryClaim] = []
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
      let token = self.next_lease_token
      self.next_lease_token = self.next_lease_token + 1L
      let expires_at_ms = now_ms + lease_ms
      let updated = {
        ..item,
        attempt: item.attempt + 1,
        state: InFlight,
        updated_at_ms: now_ms,
      }
      self.deliveries[i] = updated
      self.set_lease({
        delivery_id: updated.id,
        owner: worker_id,
        token,
        expires_at_ms,
      })
      claimed.push({
        delivery: updated,
        owner: worker_id,
        token,
        expires_at_ms,
      })
    }
  }
  claimed
}

///|
/// Extends a live lease without allowing an old owner, stale token, or late
/// heartbeat to revive work that is already eligible for recovery.
pub fn DeliveryQueue::renew_lease(
  self : DeliveryQueue,
  id : String,
  worker_id : String,
  token : Int64,
  now_ms : Int64,
  lease_ms : Int64,
) -> LeaseUpdateResult {
  if worker_id.trim().is_empty() || token <= 0L || lease_ms <= 0L {
    return LeaseInvalid
  }
  guard self.index_of(id) is Some(index) else { return LeaseNotFound }
  let item = self.deliveries[index]
  guard item.state == InFlight else { return LeaseInvalidTransition }
  guard self.active_lease(id) is Some(lease) else { return LeaseStale }
  if lease.owner != worker_id || lease.token != token {
    return LeaseStale
  }
  if lease.expires_at_ms <= now_ms {
    return LeaseExpired
  }
  let proposed = now_ms + lease_ms
  self.set_lease({
    ..lease,
    expires_at_ms: if proposed > lease.expires_at_ms {
      proposed
    } else {
      lease.expires_at_ms
    },
  })
  LeaseUpdated
}

///|
fn DeliveryQueue::apply_outcome(
  self : DeliveryQueue,
  index : Int,
  outcome : @engine.AttemptOutcome,
  now_ms : Int64,
  retry_after : String?,
  policy : @engine.RetryPolicy,
) -> Unit {
  let item = self.deliveries[index]
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
}

///|
/// Records an outcome only when the worker still owns the current lease.
/// Stale and expired completions leave the delivery untouched.
pub fn DeliveryQueue::record_claim_outcome(
  self : DeliveryQueue,
  id : String,
  worker_id : String,
  token : Int64,
  outcome : @engine.AttemptOutcome,
  now_ms : Int64,
  retry_after? : String? = None,
  policy? : @engine.RetryPolicy = @engine.RetryPolicy::default(),
) -> LeaseUpdateResult {
  if worker_id.trim().is_empty() || token <= 0L {
    return LeaseInvalid
  }
  guard self.index_of(id) is Some(index) else { return LeaseNotFound }
  let item = self.deliveries[index]
  guard item.state == InFlight else { return LeaseInvalidTransition }
  guard self.active_lease(id) is Some(lease) else { return LeaseStale }
  if lease.owner != worker_id || lease.token != token {
    return LeaseStale
  }
  if lease.expires_at_ms <= now_ms {
    return LeaseExpired
  }
  self.apply_outcome(index, outcome, now_ms, retry_after, policy)
  self.clear_lease(id)
  LeaseUpdated
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
  // Lease-aware claims must use record_claim_outcome so an old worker cannot
  // bypass fencing through this compatibility method.
  if self.active_lease(id) is Some(_) {
    return InvalidTransition
  }
  self.apply_outcome(index, outcome, now_ms, retry_after, policy)
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
  self.clear_lease(id)
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
  self.clear_lease(id)
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
