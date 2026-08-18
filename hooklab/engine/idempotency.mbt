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

///|
/// Creates a collision-resistant key for a delivery ID inside a provider or
/// tenant namespace. A length prefix keeps values such as ("a", "bc") and
/// ("ab", "c") distinct without relying on a reserved separator character.
pub fn scoped_idempotency_key(scope : String, key : String) -> String? {
  let clean_namespace = @core.trim_ascii(scope)
  let clean_key = @core.trim_ascii(key)
  if clean_namespace.is_empty() || clean_key.is_empty() {
    None
  } else {
    Some(
      clean_namespace.length().to_string() + ":" + clean_namespace + clean_key,
    )
  }
}

///|
/// Atomically checks a delivery ID within a namespace. This prevents equal
/// IDs from unrelated providers or tenants from suppressing one another.
pub fn MemoryIdempotencyStore::check_and_record_scoped(
  self : MemoryIdempotencyStore,
  scope : String,
  key : String,
  now : Int64,
) -> IdempotencyDecision {
  match scoped_idempotency_key(scope, key) {
    Some(scoped) => self.check_and_record(scoped, now)
    None => InvalidKey
  }
}
