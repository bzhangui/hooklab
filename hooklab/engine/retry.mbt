///|
pub(all) struct RetryPolicy {
  max_attempts : Int
  initial_delay_ms : Int64
  multiplier : Int64
  max_delay_ms : Int64
} derive(Eq, Debug)

///|
pub fn RetryPolicy::default() -> RetryPolicy {
  {
    max_attempts: 5,
    initial_delay_ms: 1000L,
    multiplier: 2L,
    max_delay_ms: 60000L,
  }
}

///|
pub(all) struct RetryStep {
  attempt : Int
  delay_ms : Int64
  scheduled_at_ms : Int64
} derive(Eq, Debug)

///|
pub fn RetryPolicy::validate(self : RetryPolicy) -> Bool {
  self.max_attempts >= 1 &&
  self.initial_delay_ms >= 0L &&
  self.multiplier >= 1L &&
  self.max_delay_ms >= self.initial_delay_ms
}

///|
pub fn retry_delay(policy : RetryPolicy, attempt : Int) -> Int64 {
  if attempt <= 1 {
    0L
  } else {
    let mut delay = policy.initial_delay_ms
    for i = 2; i < attempt; i = i + 1 {
      if delay >= policy.max_delay_ms / policy.multiplier {
        delay = policy.max_delay_ms
      } else {
        delay = delay * policy.multiplier
      }
    }
    if delay > policy.max_delay_ms {
      policy.max_delay_ms
    } else {
      delay
    }
  }
}

///|
/// Produces an absolute deterministic schedule. Attempt 1 is immediate.
pub fn retry_schedule(
  policy : RetryPolicy,
  start_at_ms : Int64,
) -> Array[RetryStep] {
  guard policy.validate() else { return [] }
  let steps : Array[RetryStep] = []
  let mut scheduled = start_at_ms
  for attempt = 1; attempt <= policy.max_attempts; attempt = attempt + 1 {
    let delay = retry_delay(policy, attempt)
    scheduled = scheduled + delay
    steps.push({ attempt, delay_ms: delay, scheduled_at_ms: scheduled })
  }
  steps
}

///|
pub(all) enum AttemptOutcome {
  Delivered(Int)
  Retryable(Int, String)
  Permanent(Int, String)
  TransportFailure(String)
} derive(Eq, Debug)

///|
pub(all) enum DeliveryDecision {
  Success
  RetryAfter(Int64)
  DeadLetter(String)
} derive(Eq, Debug)

///|
pub fn decide_delivery(
  policy : RetryPolicy,
  attempt : Int,
  outcome : AttemptOutcome,
) -> DeliveryDecision {
  match outcome {
    Delivered(code) if code >= 200 && code < 300 => Success
    Permanent(code, reason) => DeadLetter("HTTP \{code}: \{reason}")
    Delivered(code) =>
      DeadLetter("Unexpected success classification for HTTP \{code}")
    Retryable(code, reason) =>
      if attempt >= policy.max_attempts {
        DeadLetter("HTTP \{code} after \{attempt} attempts: \{reason}")
      } else {
        RetryAfter(retry_delay(policy, attempt + 1))
      }
    TransportFailure(reason) =>
      if attempt >= policy.max_attempts {
        DeadLetter("Transport failure after \{attempt} attempts: \{reason}")
      } else {
        RetryAfter(retry_delay(policy, attempt + 1))
      }
  }
}
