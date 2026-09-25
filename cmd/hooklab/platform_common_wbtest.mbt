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

///|
test "platform callback rejects invalid catalogs before persistence" {
  inspect(
    platform_plan("orders", "order.created", "key-1", "{}", "not-json"),
    content="{\"accepted\":false}",
  )
  inspect(
    platform_plan(
      "orders", "order.created", "key-1", "{}", "[{\"subscription_id\":\"s1\",\"endpoint_id\":\"e1\"}]",
    ),
    content="{\"accepted\":false}",
  )
}

///|
test "platform callback runs MoonBit contract validation" {
  let schema = "{\"type\":\"object\",\"required\":[\"orderId\"],\"properties\":{\"orderId\":{\"type\":\"integer\"}}}"
  inspect(
    platform_validate(
      "{\"orderId\":1}", "application/json", "order.created", schema, false,
    ),
    content="{\"valid\":true,\"issues\":[]}",
  )
  inspect(
    platform_validate(
      "{\"orderId\":\"bad\"}", "application/json", "order.created", schema, false,
    ),
    content="{\"valid\":false,\"issues\":[{\"code\":\"type\",\"location\":\"$.orderId\"}]}",
  )
}

///|
test "platform callback uses MoonBit delivery decisions" {
  inspect(
    gateway_decision_json(1, 204, "", ""),
    content="{\"decision\":\"success\",\"delay_ms\":0}",
  )
  inspect(
    gateway_decision_json(1, 503, "0", ""),
    content="{\"decision\":\"retry\",\"delay_ms\":1000}",
  )
}
