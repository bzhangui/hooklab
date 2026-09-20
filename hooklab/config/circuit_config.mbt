///|
fn parse_circuit_breakers(
  root : Json,
  routes : Array[@engine.RouteRule],
  issues : Array[ConfigIssue],
) -> Array[@delivery.CircuitPolicy] {
  let policies : Array[@delivery.CircuitPolicy] = []
  match field(root, "circuit_breakers") {
    None => ()
    Some(Array(items)) => {
      let seen : Array[String] = []
      for i = 0; i < items.length(); i = i + 1 {
        let location = "circuit_breakers[" + i.to_string() + "]"
        let item = items[i]
        if item is Object(_) {
          let mut valid = true
          let target = text_field(item, "target")
            .unwrap_or("")
            .trim()
            .to_owned()
          if target.is_empty() ||
            !(target.has_prefix("http://") || target.has_prefix("https://")) {
            valid = false
            add_issue(
              issues,
              "invalid_circuit_target",
              location + ".target",
              "A circuit breaker requires an HTTP(S) target.",
            )
          } else if seen.contains(target) {
            valid = false
            add_issue(
              issues,
              "duplicate_circuit_target",
              location + ".target",
              "Each target may have only one circuit breaker.",
            )
          } else {
            seen.push(target)
            if !routes.any(fn(route) { route.target == target }) {
              valid = false
              add_issue(
                issues,
                "unknown_circuit_target",
                location + ".target",
                "The protected target must appear in routes.",
              )
            }
          }
          let failure_threshold = match
            integer_field(item, "failure_threshold") {
            Some(value) if value >= 1 && value <= 20 => value
            _ => {
              valid = false
              add_issue(
                issues,
                "invalid_failure_threshold",
                location + ".failure_threshold",
                "Use an integer from 1 through 20.",
              )
              1
            }
          }
          let open_ms = match integer_field(item, "open_ms") {
            Some(value) if value >= 1000 && value <= 300000 => value
            _ => {
              valid = false
              add_issue(
                issues,
                "invalid_open_ms",
                location + ".open_ms",
                "Use an integer from 1000 through 300000 milliseconds.",
              )
              1000
            }
          }
          if valid {
            policies.push({ target, failure_threshold, open_ms, })
          }
        } else {
          add_issue(
            issues, "invalid_circuit_breaker", location, "Every circuit breaker must be a JSON object.",
          )
        }
      }
    }
    _ =>
      add_issue(
        issues, "invalid_circuit_breakers", "circuit_breakers", "Circuit breakers must be an array of target policies.",
      )
  }
  policies
}
