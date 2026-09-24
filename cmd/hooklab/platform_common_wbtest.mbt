///|
test "platform publication plan uses MoonBit fan-out rules" {
  let catalog =
    #|[{"subscription_id":"s1","endpoint_id":"e1","url":"https://example.com/a","key_id":"k1"},{"subscription_id":"s2","endpoint_id":"e2","url":"https://example.com/b","key_id":"k2"}]
  let result = platform_plan("orders", "order.created", "key-1", "{}", catalog)
  inspect(
    result,
    content="{\"accepted\":true,\"subscriptions\":[\"s1\",\"s2\"]}",
  )
  inspect(
    platform_plan("orders", "bad event", "key-1", "{}", catalog),
    content="{\"accepted\":false}",
  )
}
