///|
test "loads outbound applications endpoints and subscriptions" {
  let source =
    #|{
    #|  "version": 1,
    #|  "provider": "generic-hmac",
    #|  "routes": [{"name":"all","operator":"exists","target":"https://ingress.test"}],
    #|  "outbound": {
    #|    "applications": [{"id":"orders","publish_token_env":"HOOKLAB_PUBLISH_ORDERS"}],
    #|    "endpoints": [{"id":"warehouse","url":"https://warehouse.test/events","signing_secret_env":"HOOKLAB_SIGN_WAREHOUSE","key_id":"warehouse-v1"}],
    #|    "subscriptions": [{"id":"created","application":"orders","endpoint":"warehouse","event_types":["order.created","*"]}]
    #|  }
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(value) => {
      assert_eq(value.outbound_applications.length(), 1)
      assert_eq(value.outbound_applications[0].id, "orders")
      assert_eq(value.outbound_endpoints.length(), 1)
      assert_eq(value.outbound_endpoints[0].key_id, "warehouse-v1")
      assert_eq(value.outbound_subscriptions.length(), 1)
      assert_eq(value.outbound_subscriptions[0].event_types.length(), 2)
    }
    ConfigInvalid(issues) =>
      fail("unexpected issues: " + issues.length().to_string())
  }
}

///|
test "rejects inline outbound secrets and broken references" {
  let source =
    #|{
    #|  "version": 1,
    #|  "provider": "generic-hmac",
    #|  "routes": [{"name":"all","operator":"exists","target":"https://ingress.test"}],
    #|  "outbound": {
    #|    "applications": [{"id":"orders","publish_token":"leak","publish_token_env":"TOKEN"}],
    #|    "endpoints": [{"id":"warehouse","url":"file:///tmp/events","signing_secret":"leak","signing_secret_env":"SIGN","key_id":"v1"}],
    #|    "subscriptions": [{"id":"created","application":"missing","endpoint":"missing","event_types":[]}]
    #|  }
    #|}
  match parse_gateway_config(source) {
    ConfigLoaded(_) => fail("expected invalid outbound configuration")
    ConfigInvalid(issues) => {
      assert_true(has_issue(issues, "inline_secret_forbidden"))
      assert_true(has_issue(issues, "invalid_endpoint_url"))
      assert_true(has_issue(issues, "missing_event_types"))
      assert_true(has_issue(issues, "unknown_subscription_application"))
      assert_true(has_issue(issues, "unknown_subscription_endpoint"))
    }
  }
}

///|
fn outbound_config_with_url(url_json : String) -> String {
  "{\"version\":1,\"provider\":\"generic-hmac\",\"routes\":[{\"name\":\"all\",\"operator\":\"exists\",\"target\":\"https://ingress.test\"}],\"outbound\":{\"applications\":[{\"id\":\"orders\",\"publish_token_env\":\"TOKEN\"}],\"endpoints\":[{\"id\":\"warehouse\",\"url\":" +
  url_json +
  ",\"signing_secret_env\":\"SIGN\",\"key_id\":\"v1\"}],\"subscriptions\":[{\"id\":\"created\",\"application\":\"orders\",\"endpoint\":\"warehouse\",\"event_types\":[\"order.created\"]}]}}"
}

///|
test "accepts safe outbound endpoint URL forms" {
  let urls = [
    "\"https://warehouse.test/events\"", "\"http://127.0.0.1:8788/hooks\"", "\"https://[2001:db8::1]:8443/events\"",
  ]
  for url_json in urls {
    match parse_gateway_config(outbound_config_with_url(url_json)) {
      ConfigLoaded(_) => ()
      ConfigInvalid(issues) =>
        fail("unexpected issues: " + issues.length().to_string())
    }
  }
}

///|
test "rejects outbound endpoint URL credentials query and unsafe characters" {
  let urls = [
    "\"https://\"", "\"https://user@warehouse.test/events\"", "\"https://warehouse.test/events?token=secret\"",
    "\"https://warehouse.test/events#key\"", "\"https://warehouse.test\\\\events\"",
    "\" https://warehouse.test/events\"", "\"https://warehouse.test/\\tevents\"",
    "\"https://warehouse.test/\\nevents\"",
  ]
  for url_json in urls {
    match parse_gateway_config(outbound_config_with_url(url_json)) {
      ConfigLoaded(_) => fail("expected invalid outbound endpoint URL")
      ConfigInvalid(issues) =>
        assert_true(has_issue(issues, "invalid_endpoint_url"))
    }
  }
}

///|
test "rejects invalid outbound endpoint ports" {
  let urls = [
    "\"https://warehouse.test:\"", "\"https://warehouse.test:0/events\"", "\"https://warehouse.test:abc/events\"",
    "\"https://warehouse.test:65536/events\"", "\"https://[::1]:0/events\"",
  ]
  for url_json in urls {
    match parse_gateway_config(outbound_config_with_url(url_json)) {
      ConfigLoaded(_) => fail("expected invalid outbound endpoint URL")
      ConfigInvalid(issues) =>
        assert_true(has_issue(issues, "invalid_endpoint_url"))
    }
  }
}

///|
test "rejects unsafe outbound event types and key ids" {
  let source =
    #|{"version":1,"provider":"generic-hmac","routes":[{"name":"all","operator":"exists","target":"https://ingress.test"}],"outbound":{"applications":[{"id":"orders","publish_token_env":"TOKEN"}],"endpoints":[{"id":"warehouse","url":"https://warehouse.test/events","signing_secret_env":"SIGN","key_id":"bad key"}],"subscriptions":[{"id":"created","application":"orders","endpoint":"warehouse","event_types":["order created"]}]}}
  match parse_gateway_config(source) {
    ConfigLoaded(_) => fail("expected unsafe header values to be rejected")
    ConfigInvalid(issues) => {
      assert_true(has_issue(issues, "invalid_key_id"))
      assert_true(has_issue(issues, "invalid_event_type"))
    }
  }
}
