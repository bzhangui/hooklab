///|
test "queue enforces lifecycle and deterministic retry" {
  let queue = DeliveryQueue::new()
  assert_true(
    queue.enqueue("d-1", "e-1", "https://worker.test", 1000L) == Enqueued,
  )
  assert_true(
    queue.enqueue("d-1", "e-1", "https://worker.test", 1000L) ==
    DuplicateDelivery,
  )
  let first = queue.claim_due(1000L)
  assert_eq(first.length(), 1)
  assert_eq(first[0].attempt, 1)
  assert_true(first[0].state == InFlight)
  assert_true(
    queue.record_outcome("d-1", @engine.Retryable(503, "unavailable"), 1100L) ==
    Updated,
  )
  guard queue.get("d-1") is Some(scheduled) else { fail("missing delivery") }
  assert_true(scheduled.state == Scheduled)
  assert_eq(scheduled.next_attempt_at_ms, 2100L)
  assert_true(queue.claim_due(2099L).is_empty())
  assert_eq(queue.claim_due(2100L).length(), 1)
  assert_true(
    queue.record_outcome("d-1", @engine.Delivered(204), 2200L) == Updated,
  )
  guard queue.get("d-1") is Some(done) else { fail("missing delivery") }
  assert_true(done.state == Delivered)
  assert_eq(done.attempt, 2)
}

///|
test "dead letters can be replayed explicitly" {
  let queue = DeliveryQueue::new()
  let policy : @engine.RetryPolicy = {
    max_attempts: 1,
    initial_delay_ms: 10L,
    multiplier: 2L,
    max_delay_ms: 100L,
  }
  ignore(queue.enqueue("d-2", "e-2", "https://worker.test", 0L))
  ignore(queue.claim_due(0L))
  assert_true(
    queue.record_outcome(
      "d-2",
      @engine.TransportFailure("timeout"),
      1L,
      policy~,
    ) ==
    Updated,
  )
  guard queue.get("d-2") is Some(dead) else { fail("missing delivery") }
  assert_true(dead.state == DeadLettered)
  assert_true(queue.replay_dead_letter("d-2", 50L) == Updated)
  assert_eq(queue.claim_due(50L).length(), 1)
}

///|
test "ordering keys serialize related work" {
  let queue = DeliveryQueue::new()
  ignore(
    queue.enqueue(
      "d-1",
      "e-1",
      "https://worker.test",
      0L,
      ordering_key=Some("account-1"),
    ),
  )
  ignore(
    queue.enqueue(
      "d-2",
      "e-2",
      "https://worker.test",
      0L,
      ordering_key=Some("account-1"),
    ),
  )
  assert_eq(queue.claim_due(0L, limit=10).length(), 1)
  ignore(queue.record_outcome("d-1", @engine.Delivered(200), 1L))
  let second = queue.claim_due(1L, limit=10)
  assert_eq(second.length(), 1)
  assert_eq(second[0].id, "d-2")
}
