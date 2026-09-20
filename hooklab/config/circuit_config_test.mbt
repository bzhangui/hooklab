///|
test "loads opt-in circuit breakers without changing older configurations" {
  let source =
    #|{
    #|  "version":1,"provider":"generic-hmac",
    #|  "routes":[{"name":"all","operator":"exists","target":"https://worker.test/hook"}],
    #|  "circuit_breakers":[{"target":"https://worker.test/hook","failure_threshold":3,"open_ms":5000}]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(config) => {
      assert_eq(config.circuit_breakers.length(), 1)
      assert_eq(config.circuit_breakers[0].failure_threshold, 3)
      assert_eq(config.circuit_breakers[0].open_ms, 5000)
    }
    ConfigInvalid(_) => fail("expected valid circuit breaker")
  }
}

///|
test "reports invalid circuit breaker fields together" {
  let source =
    #|{
    #|  "version":1,"provider":"generic-hmac",
    #|  "routes":[{"name":"all","operator":"exists","target":"https://worker.test/hook"}],
    #|  "circuit_breakers":[
    #|    {"target":"https://unknown.test/hook","failure_threshold":0,"open_ms":999},
    #|    {"target":"https://unknown.test/hook","failure_threshold":21,"open_ms":300001},
    #|    false
    #|  ]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(_) => fail("expected invalid circuit breakers")
    ConfigInvalid(issues) => {
      assert_true(has_issue(issues, "unknown_circuit_target"))
      assert_true(has_issue(issues, "duplicate_circuit_target"))
      assert_true(has_issue(issues, "invalid_failure_threshold"))
      assert_true(has_issue(issues, "invalid_open_ms"))
      assert_true(has_issue(issues, "invalid_circuit_breaker"))
    }
  }
}
