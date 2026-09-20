///|
test "default policy serializes each target but isolates other targets" {
  let limiter = DispatchLimiter::new([])
  assert_true(limiter.try_acquire("https://a.test", 0L))
  assert_false(limiter.try_acquire("https://a.test", 0L))
  assert_true(limiter.try_acquire("https://b.test", 0L))
  limiter.release("https://a.test")
  assert_true(limiter.try_acquire("https://a.test", 1L))
}

///|
test "configured concurrency and rolling rate limits apply per target" {
  let limiter = DispatchLimiter::new([
    { target: "https://a.test", max_concurrency: 2, requests_per_second: 2, },
  ])
  assert_true(limiter.try_acquire("https://a.test", 100L))
  assert_true(limiter.try_acquire("https://a.test", 101L))
  assert_false(limiter.try_acquire("https://a.test", 102L))
  limiter.release("https://a.test")
  assert_false(limiter.try_acquire("https://a.test", 999L))
  assert_true(limiter.try_acquire("https://b.test", 999L))
  assert_true(limiter.try_acquire("https://a.test", 1100L))
}

///|
test "release cannot underflow and retry attempts consume the rate budget" {
  let limiter = DispatchLimiter::new([
    {
      target: "https://worker.test",
      max_concurrency: 1,
      requests_per_second: 1,
    },
  ])
  limiter.release("https://worker.test")
  assert_true(limiter.try_acquire("https://worker.test", 0L))
  limiter.release("https://worker.test")
  limiter.release("https://worker.test")
  assert_false(limiter.try_acquire("https://worker.test", 500L))
  assert_true(limiter.try_acquire("https://worker.test", 1000L))
}

///|
test "global ceiling bounds simultaneous attempts across targets" {
  let limiter = DispatchLimiter::new([])
  for i = 0; i < 16; i = i + 1 {
    assert_true(limiter.try_acquire("target-" + i.to_string(), 0L))
  }
  assert_false(limiter.try_acquire("target-16", 0L))
  limiter.release("target-0")
  assert_true(limiter.try_acquire("target-16", 1L))
}
