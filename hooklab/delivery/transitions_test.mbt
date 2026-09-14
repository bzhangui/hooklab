///|
test "queue rejects unsafe state transitions" {
  let queue = DeliveryQueue::new()
  ignore(queue.enqueue("d-1", "e-1", "https://worker.test", 0L))
  assert_true(
    queue.record_outcome("d-1", @engine.Delivered(200), 0L) == InvalidTransition,
  )
  assert_true(queue.cancel("d-1", 1L) == Updated)
  assert_true(queue.claim_due(1L).is_empty())
  assert_true(queue.replay_dead_letter("d-1", 1L) == InvalidTransition)
  assert_true(queue.cancel("missing", 1L) == NotFound)
}

///|
test "Retry-After never shortens local backoff" {
  let queue = DeliveryQueue::new()
  ignore(queue.enqueue("d-2", "e-2", "https://worker.test", 0L))
  ignore(queue.claim_due(0L))
  assert_true(
    queue.record_outcome(
      "d-2",
      @engine.Retryable(429, "rate limited"),
      10L,
      retry_after=Some("0"),
    ) ==
    Updated,
  )
  guard queue.get("d-2") is Some(item) else { fail("missing delivery") }
  assert_eq(item.next_attempt_at_ms, 1010L)
}
