///|
fn read_config_file(path : String) -> String? {
  if path.has_prefix("@") {
    read_text_file(path[1:].to_owned())
  } else {
    read_text_file(path)
  }
}

///|
fn do_gateway_config_check(args : Array[String]) -> Unit {
  guard args.length() >= 2 else {
    usage()
    set_exit_code(1)
    return
  }
  guard read_config_file(args[1]) is Some(source) else {
    println(
      "{\"valid\":false,\"issues\":[{\"code\":\"unreadable_config\",\"location\":\"$\",\"message\":\"Unable to read the configuration file.\"}]}",
    )
    set_exit_code(1)
    return
  }
  let result = @config.parse_gateway_config(source)
  println(@config.config_result_json(result))
  if result is @config.ConfigInvalid(_) {
    set_exit_code(2)
  }
}

///|
fn configured_secrets(value : @config.GatewayConfig) -> Array[String] {
  let input = read_environment(value.secret_env).unwrap_or("") +
    (match value.previous_secrets_env {
      Some(name) => "," + read_environment(name).unwrap_or("")
      None => ""
    })
  let secrets : Array[String] = []
  for item in input.split(",") {
    let secret = @core.trim_ascii(item.to_owned())
    if !secret.is_empty() {
      secrets.push(secret)
    }
  }
  secrets
}

///|
fn serve_configured_gateway(args : Array[String]) -> Unit {
  guard args.length() >= 2 else {
    usage()
    set_exit_code(1)
    return
  }
  guard read_config_file(args[1]) is Some(source) else {
    println("Unable to read gateway configuration: " + args[1])
    set_exit_code(1)
    return
  }
  match @config.parse_gateway_config(source) {
    @config.ConfigInvalid(issues) => {
      println(@config.config_result_json(@config.ConfigInvalid(issues)))
      set_exit_code(2)
    }
    @config.ConfigLoaded(value) => {
      let secrets = configured_secrets(value)
      guard !secrets.is_empty() else {
        println(
          "No secret was found in environment variable " +
          value.secret_env +
          ".",
        )
        set_exit_code(1)
        return
      }
      let gateway = @gateway.Gateway::new_with_transforms(
        value.routes,
        value.route_transforms,
      )
      println(
        "Loaded gateway configuration version " +
        value.version.to_string() +
        " with " +
        value.routes.length().to_string() +
        " route(s).",
      )
      println(
        "HookLab Gateway listening on http://127.0.0.1:" +
        value.port.to_string(),
      )
      println(
        "Webhook endpoint: http://127.0.0.1:" +
        value.port.to_string() +
        "/hooks/" +
        @core.provider_name(value.provider),
      )
      run_gateway_runtime(
        value.port,
        value.data_dir,
        fn(provider_name, headers_json, body, received_at) {
          gateway_accept_json(
            gateway,
            value.provider,
            secrets,
            provider_name,
            headers_json,
            body,
            received_at,
          )
        },
        gateway_decision_json,
        gateway_dashboard_html(),
      )
    }
  }
}
