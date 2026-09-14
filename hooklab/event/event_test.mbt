///|
test "event store rejects duplicate identifiers and supports queries" {
  let store = EventStore::new()
  let event : EventRecord = {
    id: "evt-1",
    provider: @core.GitHub,
    event_type: "push",
    delivery_id: Some("delivery-1"),
    body: "{\"secret\":\"value\"}",
    redacted_body: "{\"secret\":\"[REDACTED]\"}",
    received_at: 10L,
  }
  assert_true(store.append(event) == Appended)
  assert_true(store.append(event) == DuplicateEvent)
  assert_eq(store.by_provider(@core.GitHub).length(), 1)
  assert_eq(store.by_type("push").length(), 1)
  assert_true(store.get("missing") is None)
}
