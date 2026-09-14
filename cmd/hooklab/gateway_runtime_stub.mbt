///|
fn run_gateway_runtime(
  _port : Int,
  _data_dir : String,
  _handler : (String, String, String, Int64) -> String,
  _decision : (Int, Int, String, String) -> String,
  _dashboard : String,
) -> Unit {
  println("Gateway server is available in the JavaScript/Node.js build.")
  set_exit_code(1)
}
