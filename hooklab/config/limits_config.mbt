///|
fn parse_delivery_limits(
  root : Json,
  routes : Array[@engine.RouteRule],
  issues : Array[ConfigIssue],
) -> Array[@delivery.TargetLimit] {
  let limits : Array[@delivery.TargetLimit] = []
  match field(root, "delivery_limits") {
    None => ()
    Some(Array(items)) => {
      let seen : Array[String] = []
      for i = 0; i < items.length(); i = i + 1 {
        let location = "delivery_limits[" + i.to_string() + "]"
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
              "invalid_limit_target",
              location + ".target",
              "A delivery limit requires an HTTP(S) target.",
            )
          } else if seen.contains(target) {
            valid = false
            add_issue(
              issues,
              "duplicate_limit_target",
              location + ".target",
              "Each target may have only one delivery limit.",
            )
          } else {
            seen.push(target)
            if !routes.any(fn(route) { route.target == target }) {
              valid = false
              add_issue(
                issues,
                "unknown_limit_target",
                location + ".target",
                "The limited target must appear in routes.",
              )
            }
          }
          let max_concurrency = match integer_field(item, "max_concurrency") {
            Some(value) if value >= 1 && value <= 16 => value
            _ => {
              valid = false
              add_issue(
                issues,
                "invalid_max_concurrency",
                location + ".max_concurrency",
                "Use an integer from 1 through 16.",
              )
              1
            }
          }
          let requests_per_second = match field(item, "requests_per_second") {
            None => 0
            Some(_) =>
              match integer_field(item, "requests_per_second") {
                Some(value) if value >= 1 && value <= 100 => value
                _ => {
                  valid = false
                  add_issue(
                    issues,
                    "invalid_requests_per_second",
                    location + ".requests_per_second",
                    "Use an integer from 1 through 100, or omit the field.",
                  )
                  0
                }
              }
          }
          if valid {
            limits.push({ target, max_concurrency, requests_per_second, })
          }
        } else {
          add_issue(
            issues, "invalid_delivery_limit", location, "Every delivery limit must be a JSON object.",
          )
        }
      }
    }
    _ =>
      add_issue(
        issues, "invalid_delivery_limits", "delivery_limits", "Delivery limits must be an array of target policies.",
      )
  }
  limits
}
