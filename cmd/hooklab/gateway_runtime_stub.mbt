///|
fn run_gateway_runtime(
  _port : Int,
  _data_dir : String,
  _handler : (String, String, String, Int64) -> String,
  _publisher : (String, String, String, String, String) -> String,
  _signer : (String, String, String, Int64, String, String, String, String) -> String,
  _decision : (Int, Int, String, String) -> String,
  _acquire : (String, Int64) -> Bool,
  _cancel : (String) -> Unit,
  _complete : (String, Int, Int64, Int64) -> Unit,
  _circuit_state : (String, Int64) -> String,
  _metrics : () -> String,
  _outbound_catalog : String,
  _dashboard : String,
) -> Unit {
  println("Gateway server is available in the JavaScript/Node.js build.")
  set_exit_code(1)
}
