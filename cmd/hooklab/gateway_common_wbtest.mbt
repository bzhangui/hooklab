///|
test "gateway JSON strings escape every ASCII control character" {
  let value = StringBuilder()
  let controls : Array[Int] = [0, 8, 12, 31]
  for code in controls {
    value.write_char(code.unsafe_to_char())
  }
  inspect(
    gateway_json_string(value.to_string()),
    content="\"\\u0000\\u0008\\u000c\\u001f\"",
  )
}
