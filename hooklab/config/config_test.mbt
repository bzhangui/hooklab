///|
fn has_issue(issues : Array[ConfigIssue], code : String) -> Bool {
  issues.any(fn(issue) { issue.code == code })
}

///|
test "loads a versioned configuration with content routes" {
  let source =
    #|{
    #|  "version": 1,
    #|  "provider": "generic-hmac",
    #|  "secret_env": "HOOKLAB_ORDERS_SECRET",
    #|  "previous_secrets_env": null,
    #|  "port": 9001,
    #|  "data_dir": ".orders-data",
    #|  "routes": [
    #|    {"name":"paid","path":"kind","operator":"equals","expected":"invoice.paid","target":"https://billing.test/hook"},
    #|    {"name":"audit","path":"$","operator":"exists","target":"http://127.0.0.1:9090/audit"}
    #|  ]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(value) => {
      assert_eq(value.version, 1)
      assert_true(value.provider == @core.GenericHmac)
      assert_eq(value.secret_env, "HOOKLAB_ORDERS_SECRET")
      assert_true(value.previous_secrets_env is None)
      assert_eq(value.port, 9001)
      assert_eq(value.routes.length(), 2)
      assert_true(value.routes[0].operator == @engine.Equals)
      assert_true(value.routes[1].operator == @engine.Exists)
    }
    ConfigInvalid(issues) =>
      fail("unexpected issues: " + issues.length().to_string())
  }
}

///|
test "applies safe environment and runtime defaults" {
  let source =
    #|{"version":1,"provider":"github","routes":[{"name":"all","operator":"exists","target":"https://worker.test/hook"}]}
  match parse_gateway_config(source) {
    ConfigLoaded(value) => {
      assert_eq(value.secret_env, "HOOKLAB_SECRET")
      assert_true(
        value.previous_secrets_env == Some("HOOKLAB_PREVIOUS_SECRETS"),
      )
      assert_eq(value.port, 8787)
      assert_eq(value.data_dir, ".hooklab-data")
      assert_eq(value.routes[0].path, "$")
      assert_true(value.route_transforms.is_empty())
    }
    ConfigInvalid(_) => fail("expected valid defaults")
  }
}

///|
test "reports independent issues and rejects inline secrets" {
  let source =
    #|{
    #|  "version": 2,
    #|  "provider": "unknown",
    #|  "secret": "must-not-be-accepted",
    #|  "port": 70000,
    #|  "routes": [
    #|    {"name":"same","operator":"equals","target":"file:///tmp/out"},
    #|    {"name":"same","operator":"mystery","target":"https://worker.test"},
    #|    {"name":"typed","operator":"contains","expected":42,"target":"https://worker.test/typed"}
    #|  ]
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(_) => fail("expected invalid configuration")
    ConfigInvalid(issues) => {
      assert_true(has_issue(issues, "unsupported_version"))
      assert_true(has_issue(issues, "unsupported_provider"))
      assert_true(has_issue(issues, "inline_secret_forbidden"))
      assert_true(has_issue(issues, "invalid_port"))
      assert_true(has_issue(issues, "missing_expected"))
      assert_true(has_issue(issues, "invalid_expected"))
      assert_true(has_issue(issues, "invalid_target"))
      assert_true(has_issue(issues, "duplicate_route_name"))
      assert_true(has_issue(issues, "unsupported_operator"))
    }
  }
}

///|
test "reports malformed JSON without raising" {
  match parse_gateway_config("{") {
    ConfigLoaded(_) => fail("expected invalid JSON")
    ConfigInvalid(issues) => {
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].code, "invalid_json")
    }
  }
}
