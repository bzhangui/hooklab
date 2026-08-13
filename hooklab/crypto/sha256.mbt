///|
let sha256_round_constants : FixedArray[UInt] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
  0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
  0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
  0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
  0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
  0xc67178f2,
]

///|
fn rotate_right(x : UInt, n : Int) -> UInt {
  (x >> n) | (x << (32 - n))
}

///|
fn choose(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x.lnot() & z)
}

///|
fn majority(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x & z) ^ (y & z)
}

///|
fn big_sigma0(x : UInt) -> UInt {
  rotate_right(x, 2) ^ rotate_right(x, 13) ^ rotate_right(x, 22)
}

///|
fn big_sigma1(x : UInt) -> UInt {
  rotate_right(x, 6) ^ rotate_right(x, 11) ^ rotate_right(x, 25)
}

///|
fn small_sigma0(x : UInt) -> UInt {
  rotate_right(x, 7) ^ rotate_right(x, 18) ^ (x >> 3)
}

///|
fn small_sigma1(x : UInt) -> UInt {
  rotate_right(x, 17) ^ rotate_right(x, 19) ^ (x >> 10)
}

///|
fn padded_message(input : Bytes) -> Array[Byte] {
  let length = input.length()
  let bit_length = length.to_int64() * 8L
  let mut total = length + 1 + 8
  while total % 64 != 0 {
    total = total + 1
  }
  let out = Array::make(total, b'\x00')
  for i = 0; i < length; i = i + 1 {
    out[i] = input[i]
  }
  out[length] = b'\x80'
  for i = 0; i < 8; i = i + 1 {
    let shift = (7 - i) * 8
    out[total - 8 + i] = ((bit_length >> shift) & 0xffL).to_byte()
  }
  out
}

///|
/// Computes SHA-256 without delegating to a host crypto API, keeping results
/// identical on native, JavaScript and WebAssembly targets.
pub fn sha256_bytes(input : Bytes) -> Bytes {
  let message = padded_message(input)
  let state : FixedArray[UInt] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
    0x5be0cd19,
  ]
  let words = FixedArray::make(64, 0U)
  for block = 0; block < message.length(); block = block + 64 {
    for i = 0; i < 16; i = i + 1 {
      let offset = block + i * 4
      words[i] = (message[offset].to_uint() << 24) |
        (message[offset + 1].to_uint() << 16) |
        (message[offset + 2].to_uint() << 8) |
        message[offset + 3].to_uint()
    }
    for i = 16; i < 64; i = i + 1 {
      words[i] = small_sigma1(words[i - 2]) +
        words[i - 7] +
        small_sigma0(words[i - 15]) +
        words[i - 16]
    }
    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    let mut e = state[4]
    let mut f = state[5]
    let mut g = state[6]
    let mut h = state[7]
    for i = 0; i < 64; i = i + 1 {
      let t1 = h +
        big_sigma1(e) +
        choose(e, f, g) +
        sha256_round_constants[i] +
        words[i]
      let t2 = big_sigma0(a) + majority(a, b, c)
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    state[0] = state[0] + a
    state[1] = state[1] + b
    state[2] = state[2] + c
    state[3] = state[3] + d
    state[4] = state[4] + e
    state[5] = state[5] + f
    state[6] = state[6] + g
    state[7] = state[7] + h
  }
  Bytes::makei(32, fn(i) {
    let word = state[i / 4]
    let shift = (3 - i % 4) * 8
    (word >> shift).to_byte()
  })
}

///|
pub fn sha256(value : String) -> Bytes {
  sha256_bytes(@utf8.encode(value))
}

///|
pub fn bytes_to_hex(value : Bytes) -> String {
  let out = StringBuilder::new()
  for byte in value {
    out.write_string(byte.to_hex())
  }
  out.to_string()
}

///|
pub fn sha256_hex(value : String) -> String {
  bytes_to_hex(sha256(value))
}
