///|
pub struct SeenEntry {
  key : String
  expires_at : Int64
}

///|
pub(all) enum IdempotencyDecision {
  Accepted
  Duplicate
  InvalidKey
} derive(Eq, Debug)

///|
/// Deterministic in-memory idempotency store. Production integrations can
/// implement the same check-and-record semantics on a transactional database;
/// this store is useful for local tools, tests, and single-process consumers.
pub struct MemoryIdempotencyStore {
  mut entries : Array[SeenEntry]
  ttl_seconds : Int64
}

///|
pub fn MemoryIdempotencyStore::new(
  ttl_seconds? : Int64 = 86400L,
) -> MemoryIdempotencyStore {
  { entries: [], ttl_seconds }
}

///|
pub fn MemoryIdempotencyStore::size(self : MemoryIdempotencyStore) -> Int {
  self.entries.length()
}

///|
fn MemoryIdempotencyStore::purge(
  self : MemoryIdempotencyStore,
  now : Int64,
) -> Unit {
  let retained : Array[SeenEntry] = []
  for item in self.entries {
    if item.expires_at > now {
      retained.push(item)
    }
  }
  self.entries = retained
}

///|
pub fn MemoryIdempotencyStore::check_and_record(
  self : MemoryIdempotencyStore,
  key : String,
  now : Int64,
) -> IdempotencyDecision {
  if @core.trim_ascii(key).is_empty() {
    return InvalidKey
  }
  self.purge(now)
  for item in self.entries {
    if item.key == key {
      return Duplicate
    }
  }
  self.entries.push({ key, expires_at: now + self.ttl_seconds })
  Accepted
}
