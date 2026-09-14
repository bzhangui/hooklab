///|
test (b : @bench.T) {
  let body = "{\"event\":{\"type\":\"invoice.paid\",\"tenant\":\"acme\"},\"items\":[{\"sku\":\"PRO-ANNUAL\"}]}"
  let rules : Array[RouteRule] = [
    {
      name: "billing",
      path: "event.type",
      operator: Equals,
      expected: "invoice.paid",
      target: "https://billing.test/events",
    },
    {
      name: "tenant",
      path: "event.tenant",
      operator: Equals,
      expected: "acme",
      target: "https://audit.test/events",
    },
    {
      name: "sku",
      path: "items.0.sku",
      operator: StartsWith,
      expected: "PRO-",
      target: "https://provisioning.test/events",
    },
  ]
  b.bench(name="route_three_rules", fn() { b.keep(route(body, rules)) })
}
