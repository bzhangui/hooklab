///|
/// Process-local delivery latency counters. Target URLs stay private: the
/// exported snapshot uses only opaque labels assigned in first-seen order.
struct LatencyTarget {
  target : String
  total : Int64
  le_100_ms : Int64
  gt_100_le_500_ms : Int64
  gt_500_le_1000_ms : Int64
  gt_1000_le_5000_ms : Int64
  gt_5000_ms : Int64
}

///|
pub struct LatencyMetrics {
  targets : Array[LatencyTarget]
  mut total : Int64
}

///|
pub fn LatencyMetrics::new() -> LatencyMetrics {
  { targets: [], total: 0L, }
}

///|
fn LatencyMetrics::index_of(self : LatencyMetrics, target : String) -> Int? {
  for i = 0; i < self.targets.length(); i = i + 1 {
    if self.targets[i].target == target {
      return Some(i)
    }
  }
  None
}

///|
/// Record one completed HTTP attempt. Invalid durations and empty targets do
/// not affect the snapshot. Buckets are mutually exclusive ranges.
pub fn LatencyMetrics::record(
  self : LatencyMetrics,
  target : String,
  duration_ms : Int64,
) -> Unit {
  if target.is_empty() || duration_ms < 0L {
    return
  }
  let index = self.index_of(target)
  let meter = match index {
    Some(i) => self.targets[i]
    None =>
      {
        target,
        total: 0L,
        le_100_ms: 0L,
        gt_100_le_500_ms: 0L,
        gt_500_le_1000_ms: 0L,
        gt_1000_le_5000_ms: 0L,
        gt_5000_ms: 0L,
      }
  }
  let updated = if duration_ms <= 100L {
    { ..meter, total: meter.total + 1L, le_100_ms: meter.le_100_ms + 1L, }
  } else if duration_ms <= 500L {
    {
      ..meter,
      total: meter.total + 1L,
      gt_100_le_500_ms: meter.gt_100_le_500_ms + 1L,
    }
  } else if duration_ms <= 1000L {
    {
      ..meter,
      total: meter.total + 1L,
      gt_500_le_1000_ms: meter.gt_500_le_1000_ms + 1L,
    }
  } else if duration_ms <= 5000L {
    {
      ..meter,
      total: meter.total + 1L,
      gt_1000_le_5000_ms: meter.gt_1000_le_5000_ms + 1L,
    }
  } else {
    { ..meter, total: meter.total + 1L, gt_5000_ms: meter.gt_5000_ms + 1L, }
  }
  match index {
    Some(i) => self.targets[i] = updated
    None => self.targets.push(updated)
  }
  self.total = self.total + 1L
}

///|
/// A bounded, payload-free JSON snapshot for management APIs. Opaque labels
/// deliberately do not reveal URLs, paths, query strings, or credentials.
pub fn LatencyMetrics::to_json(self : LatencyMetrics) -> String {
  let entries : Array[String] = []
  for i = 0; i < self.targets.length(); i = i + 1 {
    let meter = self.targets[i]
    entries.push(
      "{\"id\":\"target-" +
      (i + 1).to_string() +
      "\",\"total\":" +
      meter.total.to_string() +
      ",\"buckets\":{\"le_100_ms\":" +
      meter.le_100_ms.to_string() +
      ",\"gt_100_le_500_ms\":" +
      meter.gt_100_le_500_ms.to_string() +
      ",\"gt_500_le_1000_ms\":" +
      meter.gt_500_le_1000_ms.to_string() +
      ",\"gt_1000_le_5000_ms\":" +
      meter.gt_1000_le_5000_ms.to_string() +
      ",\"gt_5000_ms\":" +
      meter.gt_5000_ms.to_string() +
      "}}",
    )
  }
  "{\"total\":" +
  self.total.to_string() +
  ",\"targets\":[" +
  entries.join(",") +
  "]}"
}
