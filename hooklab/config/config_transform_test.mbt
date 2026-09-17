///|
test "loads route transformations with explicit budgets" {
  let source =
    #|{
    #|  "version": 1,
    #|  "provider": "generic-hmac",
    #|  "routes": [{
    #|    "name": "billing",
    #|    "path": "kind",
    #|    "operator": "equals",
    #|    "expected": "invoice.paid",
    #|    "target": "https://billing.test/hook",
    #|    "transform": {
    #|      "max_input_bytes": 4096,
    #|      "max_output_bytes": 2048,
    #|      "max_operations": 3,
    #|      "operations": [
    #|        {"operation":"copy","from":"invoice.id","path":"metadata.invoice_id"},
    #|        {"operation":"remove","path":"customer.email"},
    #|        {"operation":"set","path":"source","value":"hooklab"}
    #|      ]
    #|    }
    #|  }]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(value) => {
      assert_eq(value.routes.length(), 1)
      assert_eq(value.route_transforms.length(), 1)
      let plan = value.route_transforms[0]
      assert_eq(plan.route_name, "billing")
      assert_eq(plan.operations.length(), 3)
      assert_eq(plan.budget.max_input_bytes, 4096)
      assert_eq(plan.budget.max_output_bytes, 2048)
      assert_eq(plan.budget.max_operations, 3)
      assert_true(plan.operations[0] is @transform.Copy(_, _))
      assert_true(plan.operations[1] is @transform.Remove(_))
      assert_true(plan.operations[2] is @transform.SetValue(_, _))
      assert_true(
        config_result_json(ConfigLoaded(value)).contains("\"transforms\":1"),
      )
    }
    ConfigInvalid(issues) =>
      fail("unexpected issues: " + issues.length().to_string())
  }
}

///|
test "reports transform schema and budget issues together" {
  let source =
    #|{
    #|  "version": 1,
    #|  "provider": "generic-hmac",
    #|  "routes": [{
    #|    "name": "bad-transform",
    #|    "operator": "exists",
    #|    "target": "https://worker.test/hook",
    #|    "transform": {
    #|      "max_input_bytes": 0,
    #|      "max_output_bytes": 2097152,
    #|      "max_operations": 1,
    #|      "operations": [
    #|        {"operation":"set","path":"a","value":1},
    #|        {"operation":"set","path":"b","value":2},
    #|        {"operation":"remove","path":"$"},
    #|        {"operation":"set","path":"missing"},
    #|        {"operation":"copy","from":"a..b","path":"copy"},
    #|        {"operation":"execute","path":"x"}
    #|      ]
    #|    }
    #|  }]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(_) => fail("expected invalid transform configuration")
    ConfigInvalid(issues) => {
      assert_true(has_issue(issues, "invalid_transform_budget"))
      assert_true(has_issue(issues, "transform_operation_budget_exceeded"))
      assert_true(has_issue(issues, "invalid_transform_path"))
      assert_true(has_issue(issues, "missing_transform_value"))
      assert_true(has_issue(issues, "unsupported_transform_operation"))
    }
  }
}
