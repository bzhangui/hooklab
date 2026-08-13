///|
pub fn hmac_sha256_bytes(key : Bytes, message : Bytes) -> Bytes {
  let block_size = 64
  let normalized = if key.length() > block_size {
    sha256_bytes(key)
  } else {
    key
  }
  let inner = Bytes::makei(block_size + message.length(), fn(i) {
    if i < block_size {
      let key_byte = if i < normalized.length() {
        normalized[i]
      } else {
        b'\x00'
      }
      key_byte ^ b'\x36'
    } else {
      message[i - block_size]
    }
  })
  let inner_hash = sha256_bytes(inner)
  let outer = Bytes::makei(block_size + 32, fn(i) {
    if i < block_size {
      let key_byte = if i < normalized.length() {
        normalized[i]
      } else {
        b'\x00'
      }
      key_byte ^ b'\x5c'
    } else {
      inner_hash[i - block_size]
    }
  })
  sha256_bytes(outer)
}

///|
pub fn hmac_sha256(key : String, message : String) -> Bytes {
  hmac_sha256_bytes(@utf8.encode(key), @utf8.encode(message))
}

///|
pub fn hmac_sha256_hex(key : String, message : String) -> String {
  bytes_to_hex(hmac_sha256(key, message))
}

///|
/// Length and content are compared without returning early. This avoids the
/// obvious prefix timing leak present in normal string equality.
pub fn constant_time_equal(left : String, right : String) -> Bool {
  let a = @utf8.encode(left)
  let b = @utf8.encode(right)
  let max_length = if a.length() > b.length() { a.length() } else { b.length() }
  let mut difference = a.length() ^ b.length()
  for i = 0; i < max_length; i = i + 1 {
    let av = if i < a.length() { a[i].to_int() } else { 0 }
    let bv = if i < b.length() { b[i].to_int() } else { 0 }
    difference = difference | (av ^ bv)
  }
  difference == 0
}
