///|
/// File and network I/O are intentionally limited to the Node.js CLI build.
fn read_text_file(_path : String) -> String? {
  None
}

///|
fn write_text_file(_path : String, _content : String) -> Bool {
  false
}

///|
fn post_webhook(_url : String, _body : String) -> Unit {
  println("Replay transport is available in the JavaScript/Node.js build.")
}

///|
fn set_exit_code(_code : Int) -> Unit {
  ()
}
