///|
test "leased claims require the current fencing token" {
  let queue = DeliveryQueue::new()
  ignore(queue.enqueue("d-lease", "e-1", "https://worker.test", 0L))
  let claimed = queue.claim_due_with_lease("worker-a", 0L, 100L)
  assert_eq(claimed.length(), 1)
  assert_eq(claimed[0].owner, "worker-a")
  assert_eq(claimed[0].token, 1L)
  assert_eq(claimed[0].expires_at_ms, 100L)
  guard queue.get_claim("d-lease") is Some(active) else {
    fail("missing active lease")
  }
  assert_eq(active.token, claimed[0].token)
  assert_true(
    queue.record_outcome("d-lease", @engine.Delivered(204), 10L) ==
    InvalidTransition,
  )
  assert_true(
    queue.record_claim_outcome(
      "d-lease",
      "worker-b",
      claimed[0].token,
      @engine.Delivered(204),
      10L,
    ) ==
    LeaseStale,
  )
  assert_true(
    queue.record_claim_outcome(
      "d-lease",
      "worker-a",
      claimed[0].token,
      @engine.Delivered(204),
      10L,
    ) ==
    LeaseUpdated,
  )
  assert_true(queue.get_claim("d-lease") is None)
  guard queue.get("d-lease") is Some(done) else { fail("missing delivery") }
  assert_true(done.state == Delivered)
}

///|
test "expired work is reclaimed with a newer token" {
  let queue = DeliveryQueue::new()
  ignore(queue.enqueue("d-expired", "e-1", "https://worker.test", 0L))
  let first = queue.claim_due_with_lease("worker-a", 0L, 100L)
  assert_eq(first.length(), 1)
  assert_true(
    queue.record_claim_outcome(
      "d-expired",
      "worker-a",
      first[0].token,
      @engine.Delivered(200),
      100L,
    ) ==
    LeaseExpired,
  )
  assert_eq(queue.recover_expired_leases(99L), 0)
  assert_eq(queue.recover_expired_leases(100L), 1)
  guard queue.get("d-expired") is Some(recovered) else {
    fail("missing recovered delivery")
  }
  assert_true(recovered.state == Scheduled)
  assert_eq(recovered.attempt, 1)
  let second = queue.claim_due_with_lease("worker-b", 100L, 100L)
  assert_eq(second.length(), 1)
  assert_true(second[0].token > first[0].token)
  assert_eq(second[0].delivery.attempt, 2)
  assert_true(
    queue.record_claim_outcome(
      "d-expired",
      "worker-a",
      first[0].token,
      @engine.Delivered(200),
      101L,
    ) ==
    LeaseStale,
  )
  assert_true(
    queue.record_claim_outcome(
      "d-expired",
      "worker-b",
      second[0].token,
      @engine.Delivered(200),
      101L,
    ) ==
    LeaseUpdated,
  )
}

///|
test "lease renewal validates ownership and never shortens expiry" {
  let queue = DeliveryQueue::new()
  ignore(queue.enqueue("d-renew", "e-1", "https://worker.test", 0L))
  let claim = queue.claim_due_with_lease("worker-a", 0L, 100L)[0]
  assert_true(
    queue.renew_lease("d-renew", "worker-a", claim.token + 1L, 50L, 100L) ==
    LeaseStale,
  )
  assert_true(
    queue.renew_lease("d-renew", "worker-a", claim.token, 50L, 100L) ==
    LeaseUpdated,
  )
  guard queue.get_claim("d-renew") is Some(renewed) else {
    fail("missing renewed lease")
  }
  assert_eq(renewed.expires_at_ms, 150L)
  assert_true(
    queue.renew_lease("d-renew", "worker-a", claim.token, 60L, 10L) ==
    LeaseUpdated,
  )
  guard queue.get_claim("d-renew") is Some(not_shortened) else {
    fail("missing renewed lease")
  }
  assert_eq(not_shortened.expires_at_ms, 150L)
  assert_true(
    queue.renew_lease("d-renew", "worker-a", claim.token, 150L, 10L) ==
    LeaseExpired,
  )
}

///|
test "invalid lease requests create no claims" {
  let queue = DeliveryQueue::new()
  ignore(queue.enqueue("d-invalid", "e-1", "https://worker.test", 0L))
  assert_true(queue.claim_due_with_lease("", 0L, 100L).is_empty())
  assert_true(queue.claim_due_with_lease("worker-a", 0L, 0L).is_empty())
  assert_true(
    queue.renew_lease("missing", "worker-a", 1L, 0L, 100L) == LeaseNotFound,
  )
  assert_true(
    queue.record_claim_outcome(
      "missing",
      "worker-a",
      1L,
      @engine.Delivered(200),
      0L,
    ) ==
    LeaseNotFound,
  )
}
