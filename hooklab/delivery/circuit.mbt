///|
/// An opt-in, process-local circuit policy for one outbound target.
/// Configuration validation enforces the public ranges.
pub(all) struct CircuitPolicy {
  target : String
  failure_threshold : Int
  open_ms : Int
} derive(Eq, Debug)

///|
/// Only retryable failures count toward opening a circuit. A neutral outcome
/// neither increments nor clears the failure count since the last success.
pub(all) enum CircuitOutcome {
  Success
  RetryableFailure
  Neutral
} derive(Eq, Debug)

///|
priv enum CircuitPhase {
  Closed
  Open
  HalfOpen
}

///|
struct CircuitMeter {
  target : String
  phase : CircuitPhase
  consecutive_failures : Int
  closed_in_flight : Int
  open_since_ms : Int64
  probe_in_flight : Bool
}

///|
/// Admission and outcome tracking for explicitly configured targets. Targets
/// without a policy are not circuit-limited, preserving old gateway behavior.
pub struct CircuitBreaker {
  policies : Array[CircuitPolicy]
  meters : Array[CircuitMeter]
}

///|
pub fn CircuitBreaker::new(policies : Array[CircuitPolicy]) -> CircuitBreaker {
  { policies, meters: [], }
}

///|
fn CircuitBreaker::policy_for(
  self : CircuitBreaker,
  target : String,
) -> CircuitPolicy? {
  for policy in self.policies {
    if policy.target == target {
      return Some(policy)
    }
  }
  None
}

///|
fn CircuitBreaker::index_of(self : CircuitBreaker, target : String) -> Int? {
  for i = 0; i < self.meters.length(); i = i + 1 {
    if self.meters[i].target == target {
      return Some(i)
    }
  }
  None
}

///|
fn CircuitBreaker::store(
  self : CircuitBreaker,
  index : Int?,
  meter : CircuitMeter,
) -> Unit {
  match index {
    Some(i) => self.meters[i] = meter
    None => self.meters.push(meter)
  }
}

///|
/// Reserves a closed-state attempt or the sole half-open probe. When a circuit
/// opens while other closed-state attempts are running, it waits for them to
/// drain before allowing any probe. This prevents their late outcomes from
/// being mistaken for the probe's result.
pub fn CircuitBreaker::try_acquire(
  self : CircuitBreaker,
  target : String,
  now_ms : Int64,
) -> Bool {
  let policy = match self.policy_for(target) {
    Some(policy) => policy
    None => return true
  }
  if target.is_empty() ||
    now_ms < 0L ||
    policy.failure_threshold < 1 ||
    policy.failure_threshold > 20 ||
    policy.open_ms < 1000 ||
    policy.open_ms > 300000 {
    return false
  }
  let index = self.index_of(target)
  let meter = match index {
    Some(i) => self.meters[i]
    None =>
      {
        target,
        phase: Closed,
        consecutive_failures: 0,
        closed_in_flight: 0,
        open_since_ms: 0L,
        probe_in_flight: false,
      }
  }
  match meter.phase {
    Closed => {
      self.store(index, {
        ..meter,
        closed_in_flight: meter.closed_in_flight + 1,
      })
      true
    }
    Open => {
      if meter.closed_in_flight > 0 ||
        now_ms < meter.open_since_ms ||
        now_ms - meter.open_since_ms < policy.open_ms.to_int64() {
        return false
      }
      self.store(index, { ..meter, phase: HalfOpen, probe_in_flight: true, })
      true
    }
    HalfOpen => {
      if meter.probe_in_flight {
        return false
      }
      self.store(index, { ..meter, probe_in_flight: true, })
      true
    }
  }
}

///|
/// Completes a reserved attempt. Outcomes from closed-state requests that
/// finish after another request opened the circuit only drain the reservation.
pub fn CircuitBreaker::complete(
  self : CircuitBreaker,
  target : String,
  outcome : CircuitOutcome,
  now_ms : Int64,
) -> Unit {
  let policy = match self.policy_for(target) {
    Some(policy) => policy
    None => return
  }
  let index = match self.index_of(target) {
    Some(index) => index
    None => return
  }
  let meter = self.meters[index]
  let opened_at = if now_ms >= 0L { now_ms } else { 0L }
  match meter.phase {
    Closed => {
      if meter.closed_in_flight <= 0 {
        return
      }
      let draining = { ..meter, closed_in_flight: meter.closed_in_flight - 1, }
      self.meters[index] = match outcome {
        Success => { ..draining, consecutive_failures: 0, }
        Neutral => draining
        RetryableFailure => {
          let failures = draining.consecutive_failures + 1
          if failures >= policy.failure_threshold {
            {
              ..draining,
              phase: Open,
              consecutive_failures: failures,
              open_since_ms: opened_at,
            }
          } else {
            { ..draining, consecutive_failures: failures, }
          }
        }
      }
    }
    Open =>
      if meter.closed_in_flight > 0 {
        self.meters[index] = {
          ..meter,
          closed_in_flight: meter.closed_in_flight - 1,
        }
      }
    HalfOpen => {
      if !meter.probe_in_flight {
        return
      }
      self.meters[index] = match outcome {
        Success =>
          {
            ..meter,
            phase: Closed,
            consecutive_failures: 0,
            probe_in_flight: false,
          }
        RetryableFailure =>
          {
            ..meter,
            phase: Open,
            consecutive_failures: policy.failure_threshold,
            open_since_ms: opened_at,
            probe_in_flight: false,
          }
        Neutral => { ..meter, probe_in_flight: false, }
      }
    }
  }
}

///|
/// Releases an admission if a dispatch fails before any network attempt. It
/// does not change the failure count or pretend the target recovered.
pub fn CircuitBreaker::cancel(self : CircuitBreaker, target : String) -> Unit {
  if self.policy_for(target) is None {
    return
  }
  let index = match self.index_of(target) {
    Some(index) => index
    None => return
  }
  let meter = self.meters[index]
  match meter.phase {
    Closed | Open =>
      if meter.closed_in_flight > 0 {
        self.meters[index] = {
          ..meter,
          closed_in_flight: meter.closed_in_flight - 1,
        }
      }
    HalfOpen =>
      if meter.probe_in_flight {
        self.meters[index] = { ..meter, probe_in_flight: false, }
      }
  }
}

///|
/// Read-only status for diagnostics; elapsed cooldown is reported as half-open
/// only after all pre-open requests have drained.
pub fn CircuitBreaker::state(
  self : CircuitBreaker,
  target : String,
  now_ms : Int64,
) -> String {
  let policy = match self.policy_for(target) {
    Some(policy) => policy
    None => return "disabled"
  }
  let meter = match self.index_of(target) {
    Some(index) => self.meters[index]
    None => return "closed"
  }
  match meter.phase {
    Closed => "closed"
    HalfOpen => "half_open"
    Open =>
      if meter.closed_in_flight == 0 &&
        now_ms >= meter.open_since_ms &&
        now_ms - meter.open_since_ms >= policy.open_ms.to_int64() {
        "half_open"
      } else {
        "open"
      }
  }
}
