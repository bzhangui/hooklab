///|
test "SHA-256 standard vectors" {
  inspect(
    sha256_hex(""),
    content="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  inspect(
    sha256_hex("abc"),
    content="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  inspect(
    sha256_hex("The quick brown fox jumps over the lazy dog"),
    content="d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
  )
}

///|
test "HMAC-SHA256 RFC 4231 compatible vector" {
  inspect(
    hmac_sha256_hex("key", "The quick brown fox jumps over the lazy dog"),
    content="f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
  )
}

///|
test "constant-time equality checks length and content" {
  assert_true(constant_time_equal("abc", "abc"))
  assert_false(constant_time_equal("abc", "abd"))
  assert_false(constant_time_equal("abc", "abc0"))
}
