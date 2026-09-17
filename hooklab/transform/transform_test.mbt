///|
test "set, remove, and copy produce deterministic JSON" {
  let result = apply(
    (
      #|{"kind":"invoice.paid","customer":{"email":"private@example.test"},"items":[{"sku":"A1"}]}
    ),
    [
      Copy("items.0.sku", "customer.sku"),
      Remove("customer.email"),
      SetValue("source", Json::string("hooklab")),
    ],
    { max_input_bytes: 1024, max_output_bytes: 1024, max_operations: 3, },
  )
  match result {
    Transformed(body, count) => {
      assert_eq(count, 3)
      assert_eq(
        body,
        (
          #|{"kind":"invoice.paid","customer":{"sku":"A1"},"items":[{"sku":"A1"}],"source":"hooklab"}
        ),
      )
    }
    TransformRejected(failure) => fail(failure.message)
  }
}

///|
test "supports replacing the document root" {
  match
    apply("{\"private\":true}", [SetValue("$", { "status": "accepted" })], {
      max_input_bytes: 64,
      max_output_bytes: 64,
      max_operations: 1,
    }) {
    Transformed(body, _) => assert_eq(body, "{\"status\":\"accepted\"}")
    TransformRejected(failure) => fail(failure.message)
  }
}

///|
test "rejects input, operation, and output budget overruns" {
  let tiny_input = apply(
    (
      #|{"value":"large"}
    ),
    [],
    { max_input_bytes: 4, max_output_bytes: 100, max_operations: 1, },
  )
  assert_true(tiny_input is TransformRejected({ code: InputTooLarge, .. }))
  let too_many = apply(
    (
      #|{}
    ),
    [SetValue("a", Json::string("1")), SetValue("b", Json::string("2"))],
    { max_input_bytes: 100, max_output_bytes: 100, max_operations: 1, },
  )
  assert_true(
    too_many is TransformRejected({ code: OperationLimitExceeded, .. }),
  )
  let tiny_output = apply(
    (
      #|{}
    ),
    [SetValue("value", Json::string("too-large"))],
    { max_input_bytes: 100, max_output_bytes: 4, max_operations: 1, },
  )
  assert_true(tiny_output is TransformRejected({ code: OutputTooLarge, .. }))
}

///|
test "rejects malformed JSON and missing paths without partial output" {
  assert_true(
    apply("{", [], TransformBudget::safe_default())
    is TransformRejected({ code: InvalidJson, .. }),
  )
  assert_true(
    apply(
      (
        #|{"customer":{}}
      ),
      [Remove("customer.email")],
      TransformBudget::safe_default(),
    )
    is TransformRejected({ code: PathNotFound, .. }),
  )
}

///|
test "budgets count UTF-8 bytes instead of UTF-16 code units" {
  assert_true(
    apply("{\"value\":\"中\"}", [], {
      max_input_bytes: 14,
      max_output_bytes: 100,
      max_operations: 1,
    })
    is TransformRejected({ code: InputTooLarge, .. }),
  )
}
