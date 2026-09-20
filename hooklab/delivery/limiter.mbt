///|
/// Per-target policy. A zero request rate means no rate cap; concurrency is
/// still bounded. Configuration validation enforces the public ranges.
pub(all) struct TargetLimit {
  target : String
  max_concurrency : Int
  requests_per_second : Int
} derive(Eq, Debug)

///|
struct TargetMeter {
  target : String
  in_flight : Int
  starts_ms : Array[Int64]
}

///|
/// Process-local admission state for outbound attempts. Retries and manual
/// replays pass through the same gate as first attempts.
pub struct DispatchLimiter {
  limits : Array[TargetLimit]
  meters : Array[TargetMeter]
}

///|
pub fn DispatchLimiter::new(limits : Array[TargetLimit]) -> DispatchLimiter {
  { limits, meters: [], }
}

///|
fn DispatchLimiter::policy_for(
  self : DispatchLimiter,
  target : String,
) -> TargetLimit {
  for limit in self.limits {
    if limit.target == target {
      return limit
    }
  }
  { target, max_concurrency: 1, requests_per_second: 0, }
}

///|
fn DispatchLimiter::index_of(self : DispatchLimiter, target : String) -> Int? {
  for i = 0; i < self.meters.length(); i = i + 1 {
    if self.meters[i].target == target {
      return Some(i)
    }
  }
  None
}

///|
/// A hard process-wide ceiling prevents unlimited configured targets from
/// creating unbounded simultaneous HTTP requests.
pub fn DispatchLimiter::try_acquire(
  self : DispatchLimiter,
  target : String,
  now_ms : Int64,
) -> Bool {
  if target.is_empty() || now_ms < 0L {
    return false
  }
  let policy = self.policy_for(target)
  if policy.max_concurrency <= 0 ||
    policy.max_concurrency > 16 ||
    policy.requests_per_second < 0 ||
    policy.requests_per_second > 100 {
    return false
  }
  let mut global_in_flight = 0
  for meter in self.meters {
    global_in_flight = global_in_flight + meter.in_flight
  }
  if global_in_flight >= 16 {
    return false
  }
  let index = self.index_of(target)
  let meter = match index {
    Some(i) => self.meters[i]
    None => { target, in_flight: 0, starts_ms: [], }
  }
  if meter.in_flight >= policy.max_concurrency {
    return false
  }
  let recent : Array[Int64] = []
  if policy.requests_per_second > 0 {
    for started in meter.starts_ms {
      // Future timestamps remain active if the clock moves backwards.
      if started > now_ms || now_ms - started < 1000L {
        recent.push(started)
      }
    }
    if recent.length() >= policy.requests_per_second {
      return false
    }
    recent.push(now_ms)
  }
  let updated = { target, in_flight: meter.in_flight + 1, starts_ms: recent, }
  match index {
    Some(i) => self.meters[i] = updated
    None => self.meters.push(updated)
  }
  true
}

///|
/// Releases one in-flight slot after the HTTP attempt finishes. Unknown and
/// duplicate releases are ignored, so a caller cannot create negative usage.
pub fn DispatchLimiter::release(
  self : DispatchLimiter,
  target : String,
) -> Unit {
  match self.index_of(target) {
    Some(index) => {
      let meter = self.meters[index]
      if meter.in_flight > 0 {
        self.meters[index] = { ..meter, in_flight: meter.in_flight - 1, }
      }
    }
    None => ()
  }
}
