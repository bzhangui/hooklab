///|
test "unconfigured targets remain circuit-disabled" {
  let breaker = CircuitBreaker::new([])
  assert_eq(breaker.state("https://a.test", 0L), "disabled")
  assert_true(breaker.try_acquire("https://a.test", 0L))
  assert_true(breaker.try_acquire("https://a.test", 0L))
  breaker.complete("https://a.test", RetryableFailure, 1L)
  breaker.cancel("https://a.test")
  assert_true(breaker.try_acquire("https://a.test", 2L))
}

///|
test "retryable failures since last success trip configured circuit" {
  let breaker = CircuitBreaker::new([
    { target: "https://a.test", failure_threshold: 2, open_ms: 1000, },
  ])
  assert_true(breaker.try_acquire("https://a.test", 0L))
  breaker.complete("https://a.test", RetryableFailure, 1L)
  assert_eq(breaker.state("https://a.test", 1L), "closed")
  assert_true(breaker.try_acquire("https://a.test", 2L))
  breaker.complete("https://a.test", Neutral, 3L)
  assert_true(breaker.try_acquire("https://a.test", 4L))
  breaker.complete("https://a.test", Success, 5L)
  assert_true(breaker.try_acquire("https://a.test", 6L))
  breaker.complete("https://a.test", RetryableFailure, 7L)
  assert_eq(breaker.state("https://a.test", 7L), "closed")
  assert_true(breaker.try_acquire("https://a.test", 8L))
  breaker.complete("https://a.test", RetryableFailure, 9L)
  assert_eq(breaker.state("https://a.test", 9L), "open")
  assert_false(breaker.try_acquire("https://a.test", 1008L))
  assert_true(breaker.try_acquire("https://b.test", 1008L))
}

///|
test "cooldown permits one half-open probe and success closes" {
  let breaker = CircuitBreaker::new([
    { target: "https://a.test", failure_threshold: 1, open_ms: 1000, },
  ])
  assert_true(breaker.try_acquire("https://a.test", 10L))
  breaker.complete("https://a.test", RetryableFailure, 20L)
  assert_false(breaker.try_acquire("https://a.test", 1019L))
  assert_eq(breaker.state("https://a.test", 1020L), "half_open")
  assert_true(breaker.try_acquire("https://a.test", 1020L))
  assert_false(breaker.try_acquire("https://a.test", 1021L))
  breaker.complete("https://a.test", Success, 1022L)
  assert_eq(breaker.state("https://a.test", 1022L), "closed")
  assert_true(breaker.try_acquire("https://a.test", 1023L))
}

///|
test "failed probe reopens and neutral probe leaves one slot" {
  let breaker = CircuitBreaker::new([
    { target: "https://a.test", failure_threshold: 1, open_ms: 1000, },
  ])
  assert_true(breaker.try_acquire("https://a.test", 0L))
  breaker.complete("https://a.test", RetryableFailure, 1L)
  assert_true(breaker.try_acquire("https://a.test", 1001L))
  breaker.complete("https://a.test", Neutral, 1002L)
  assert_eq(breaker.state("https://a.test", 1002L), "half_open")
  assert_true(breaker.try_acquire("https://a.test", 1003L))
  breaker.complete("https://a.test", RetryableFailure, 1004L)
  assert_eq(breaker.state("https://a.test", 1004L), "open")
  assert_false(breaker.try_acquire("https://a.test", 2003L))
  assert_true(breaker.try_acquire("https://a.test", 2004L))
}

///|
test "cancel releases half-open probe without declaring recovery" {
  let breaker = CircuitBreaker::new([
    { target: "https://a.test", failure_threshold: 1, open_ms: 1000, },
  ])
  assert_true(breaker.try_acquire("https://a.test", 0L))
  breaker.complete("https://a.test", RetryableFailure, 1L)
  assert_false(breaker.try_acquire("https://a.test", 0L))
  assert_true(breaker.try_acquire("https://a.test", 1001L))
  breaker.cancel("https://a.test")
  breaker.cancel("https://a.test")
  assert_eq(breaker.state("https://a.test", 1002L), "half_open")
  assert_true(breaker.try_acquire("https://a.test", 1002L))
  assert_false(breaker.try_acquire("https://a.test", 1002L))
}

///|
test "old concurrent requests drain before half-open and cannot close it" {
  let breaker = CircuitBreaker::new([
    { target: "https://a.test", failure_threshold: 1, open_ms: 1000, },
  ])
  assert_true(breaker.try_acquire("https://a.test", 0L))
  assert_true(breaker.try_acquire("https://a.test", 0L))
  breaker.complete("https://a.test", RetryableFailure, 1L)
  assert_eq(breaker.state("https://a.test", 1001L), "open")
  assert_false(breaker.try_acquire("https://a.test", 1001L))
  breaker.complete("https://a.test", Success, 1002L)
  assert_eq(breaker.state("https://a.test", 1002L), "half_open")
  assert_true(breaker.try_acquire("https://a.test", 1002L))
  assert_false(breaker.try_acquire("https://a.test", 1003L))
  breaker.complete("https://a.test", RetryableFailure, 1004L)
  assert_eq(breaker.state("https://a.test", 1004L), "open")
}

///|
test "invalid explicit policies fail closed" {
  let breaker = CircuitBreaker::new([
    { target: "https://a.test", failure_threshold: 0, open_ms: 1000, },
  ])
  assert_false(breaker.try_acquire("https://a.test", 0L))
  assert_true(breaker.try_acquire("https://b.test", 0L))
}
