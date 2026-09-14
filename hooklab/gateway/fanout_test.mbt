///|
test "gateway fans one verified event out to independent targets" {
  let gateway = Gateway::new([
    {
      name: "audit",
      path: "$",
      operator: @engine.Exists,
      expected: "",
      target: "https://audit.test/events",
    },
    {
      name: "billing",
      path: "status",
      operator: @engine.Equals,
      expected: "paid",
      target: "https://billing.test/events",
    },
  ])
  let request = generic_request("fanout-1", "{\"status\":\"paid\"}")
  match gateway.accept(request, ["gateway-secret"], 1000L) {
    Accepted(_, deliveries) => {
      assert_eq(deliveries.length(), 2)
      assert_true(deliveries[0].id != deliveries[1].id)
    }
    Rejected(failure) => fail(failure.message)
  }
}
