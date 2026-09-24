///|
fn run_platform_runtime(
  _port : Int,
  _plan : (String, String, String, String, String) -> String,
  _sign : (String, Int64, String, String, String, String) -> String,
  _decide : (Int, Int, String, String) -> String,
  _validate : (String, String, String, String, Bool) -> String,
  _compatible : (String, String) -> Bool,
) -> Unit {
  println(
    "The PostgreSQL platform is available in the JavaScript/Node.js build.",
  )
  set_exit_code(1)
}
