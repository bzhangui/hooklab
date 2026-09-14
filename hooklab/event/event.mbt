///|
/// An accepted webhook. `body` is retained for authorized delivery and replay;
/// logs and user interfaces must use `redacted_body` instead.
pub(all) struct EventRecord {
  id : String
  provider : @core.Provider
  event_type : String
  delivery_id : String?
  body : String
  redacted_body : String
  received_at : Int64
} derive(Eq, Debug)

///|
pub(all) enum AppendResult {
  Appended
  DuplicateEvent
  InvalidEvent
} derive(Eq, Debug)

///|
pub struct EventStore {
  events : Array[EventRecord]
}

///|
pub fn EventStore::new() -> EventStore {
  { events: [], }
}

///|
pub fn EventStore::size(self : EventStore) -> Int {
  self.events.length()
}

///|
pub fn EventStore::all(self : EventStore) -> Array[EventRecord] {
  self.events.copy()
}

///|
pub fn EventStore::get(self : EventStore, id : String) -> EventRecord? {
  for item in self.events {
    if item.id == id {
      return Some(item)
    }
  }
  None
}

///|
pub fn EventStore::append(
  self : EventStore,
  event : EventRecord,
) -> AppendResult {
  if event.id.trim().is_empty() || event.event_type.trim().is_empty() {
    return InvalidEvent
  }
  if self.get(event.id) is Some(_) {
    return DuplicateEvent
  }
  self.events.push(event)
  Appended
}

///|
pub fn EventStore::by_provider(
  self : EventStore,
  provider : @core.Provider,
) -> Array[EventRecord] {
  self.events.filter(fn(item) { item.provider == provider })
}

///|
pub fn EventStore::by_type(
  self : EventStore,
  event_type : String,
) -> Array[EventRecord] {
  self.events.filter(fn(item) { item.event_type == event_type })
}
