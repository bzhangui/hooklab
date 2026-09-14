///|
/// Extracts a string from a verified provider payload without reserializing the
/// body. It is used only after signature verification for event metadata.
fn payload_string_at_path(body : String, path : Array[String]) -> String? {
  let parsed = @json.parse(body) catch { _ => return None }
  let mut current = parsed
  for key in path {
    match current {
      Object(values) =>
        match values.get_from_string(key) {
          Some(next) => current = next
          None => return None
        }
      _ => return None
    }
  }
  match current {
    String(value) => Some(value)
    _ => None
  }
}
