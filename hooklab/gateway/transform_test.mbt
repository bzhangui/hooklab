///|
test "gateway applies a route transform to the delivery payload" {
  let routes : Array[@engine.RouteRule] = [
    {
      name: "billing",
      path: "kind",
      operator: @engine.Equals,
      expected: "invoice.paid",
      target: "https://billing.test/hook",
    },
  ]
  let transforms : Array[@transform.RouteTransform] = [
    {
      route_name: "billing",
      operations: [
        @transform.Copy("invoice_id", "customer.invoice_id"),
        @transform.Remove("customer.email"),
      ],
      budget: {
        max_input_bytes: 1024,
        max_output_bytes: 1024,
        max_operations: 2,
      },
    },
  ]
  let gateway = Gateway::new_with_transforms(routes, transforms)
  let request = generic_request(
    "transform-1",
    (
      #|{"kind":"invoice.paid","invoice_id":"inv-7","customer":{"email":"private@example.test"}}
    ),
  )
  match gateway.accept(request, ["gateway-secret"], 1000L) {
    Accepted(_, deliveries) => {
      assert_eq(deliveries.length(), 1)
      assert_true(
        deliveries[0].payload ==
        Some(
          (
            #|{"kind":"invoice.paid","invoice_id":"inv-7","customer":{"invoice_id":"inv-7"}}
          ),
        ),
      )
    }
    Rejected(failure) => fail(failure.message)
  }
}

///|
test "transform failure is atomic and does not consume idempotency" {
  let routes : Array[@engine.RouteRule] = [
    {
      name: "safe",
      path: "$",
      operator: @engine.Exists,
      expected: "",
      target: "https://worker.test/hook",
    },
  ]
  let transforms : Array[@transform.RouteTransform] = [
    {
      route_name: "safe",
      operations: [@transform.Remove("secret")],
      budget: {
        max_input_bytes: 1024,
        max_output_bytes: 1024,
        max_operations: 1,
      },
    },
  ]
  let gateway = Gateway::new_with_transforms(routes, transforms)
  match
    gateway.accept(
      generic_request("transform-retry", "{\"status\":\"ready\"}"),
      ["gateway-secret"],
      1000L,
    ) {
    Rejected(failure) => {
      assert_true(failure.code == @core.InvalidPayload)
      assert_true(failure.stage == @core.Routing)
    }
    Accepted(_, _) => fail("expected transformation rejection")
  }
  assert_eq(gateway.stats().events, 0)
  match
    gateway.accept(
      generic_request(
        "transform-retry", "{\"status\":\"ready\",\"secret\":\"remove-me\"}",
      ),
      ["gateway-secret"],
      1001L,
    ) {
    Accepted(_, deliveries) => {
      assert_eq(deliveries.length(), 1)
      assert_true(deliveries[0].payload == Some("{\"status\":\"ready\"}"))
    }
    Rejected(failure) => fail(failure.message)
  }
  assert_eq(gateway.stats().events, 1)
}
