///|
test "latency histogram starts empty and ignores invalid samples" {
  let metrics = LatencyMetrics::new()
  assert_eq(metrics.to_json(), "{\"total\":0,\"targets\":[]}")
  metrics.record("https://example.test", -1L)
  metrics.record("", 20L)
  assert_eq(metrics.to_json(), "{\"total\":0,\"targets\":[]}")
}

///|
test "latency boundaries enter exactly one bucket" {
  let metrics = LatencyMetrics::new()
  for duration in [0L, 100L, 101L, 500L, 501L, 1000L, 1001L, 5000L, 5001L] {
    metrics.record("https://example.test", duration)
  }
  assert_eq(
    metrics.to_json(),
    "{\"total\":9,\"targets\":[{\"id\":\"target-1\",\"total\":9,\"buckets\":{\"le_100_ms\":2,\"gt_100_le_500_ms\":2,\"gt_500_le_1000_ms\":2,\"gt_1000_le_5000_ms\":2,\"gt_5000_ms\":1}}]}",
  )
}

///|
test "latency metrics isolate targets and never expose target URL secrets" {
  let metrics = LatencyMetrics::new()
  let first = "https://user:password@example.test/private?api_key=top-secret"
  metrics.record(first, 101L)
  metrics.record("https://other.test/hooks", 5001L)
  metrics.record(first, 500L)
  let json = metrics.to_json()
  assert_eq(
    json, "{\"total\":3,\"targets\":[{\"id\":\"target-1\",\"total\":2,\"buckets\":{\"le_100_ms\":0,\"gt_100_le_500_ms\":2,\"gt_500_le_1000_ms\":0,\"gt_1000_le_5000_ms\":0,\"gt_5000_ms\":0}},{\"id\":\"target-2\",\"total\":1,\"buckets\":{\"le_100_ms\":0,\"gt_100_le_500_ms\":0,\"gt_500_le_1000_ms\":0,\"gt_1000_le_5000_ms\":0,\"gt_5000_ms\":1}}]}",
  )
  assert_false(json.contains("password"))
  assert_false(json.contains("api_key"))
  assert_false(json.contains("top-secret"))
}
