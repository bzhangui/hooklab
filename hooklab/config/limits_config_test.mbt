///|
test "loads target limits without changing older configurations" {
  let source =
    #|{
    #|  "version":1,"provider":"generic-hmac",
    #|  "routes":[{"name":"all","operator":"exists","target":"https://worker.test/hook"}],
    #|  "delivery_limits":[{"target":"https://worker.test/hook","max_concurrency":2,"requests_per_second":5}]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(config) => {
      assert_eq(config.delivery_limits.length(), 1)
      assert_eq(config.delivery_limits[0].max_concurrency, 2)
      assert_eq(config.delivery_limits[0].requests_per_second, 5)
    }
    ConfigInvalid(_) => fail("expected valid delivery limits")
  }
}

///|
test "reports invalid and duplicate target limits together" {
  let source =
    #|{
    #|  "version":1,"provider":"generic-hmac",
    #|  "routes":[{"name":"all","operator":"exists","target":"https://worker.test/hook"}],
    #|  "delivery_limits":[
    #|    {"target":"https://unknown.test/hook","max_concurrency":0,"requests_per_second":101},
    #|    {"target":"https://unknown.test/hook","max_concurrency":17},
    #|    42
    #|  ]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(_) => fail("expected invalid limits")
    ConfigInvalid(issues) => {
      assert_true(has_issue(issues, "unknown_limit_target"))
      assert_true(has_issue(issues, "duplicate_limit_target"))
      assert_true(has_issue(issues, "invalid_max_concurrency"))
      assert_true(has_issue(issues, "invalid_requests_per_second"))
      assert_true(has_issue(issues, "invalid_delivery_limit"))
    }
  }
}
