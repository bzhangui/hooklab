///|
fn contract_issues_json(issues : Array[@contract.ContractIssue]) -> String {
  let parts : Array[String] = []
  for issue in issues {
    parts.push(
      "{\"code\":" +
      gateway_json_string(issue.code) +
      ",\"location\":" +
      gateway_json_string(issue.location) +
      ",\"message\":" +
      gateway_json_string(issue.message) +
      "}",
    )
  }
  "[" + parts.join(",") + "]"
}

///|
fn do_contract_check(args : Array[String]) -> Unit {
  guard args.length() >= 5 else {
    usage()
    set_exit_code(1)
    return
  }
  guard provider_from_string(args[1]) is Some(provider) else {
    println("Unknown provider: " + args[1])
    set_exit_code(1)
    return
  }
  guard body_from_arg(args[2]) is Some(body) else {
    println("Unable to read body file.")
    set_exit_code(1)
    return
  }
  let paths : Array[String] = []
  for item in args[4].split(",") {
    let path = @core.trim_ascii(item.to_owned())
    if !path.is_empty() {
      paths.push(path)
    }
  }
  let max_body_chars = if args.length() > 5 {
    try @string.parse_int(args[5]) catch {
      _ => 1048576
    } noraise {
      value => value
    }
  } else {
    1048576
  }
  let request : @core.WebhookRequest = {
    provider,
    headers: [],
    body,
    received_at: current_seconds(),
  }
  let contract : @contract.WebhookContract = {
    name: "cli-contract",
    provider,
    event_type: Some(args[3]),
    required_headers: [],
    required_paths: paths,
    max_body_chars,
  }
  match @contract.validate(request, args[3], contract) {
    @contract.Valid => println("{\"status\":\"valid\",\"issues\":[]}")
    @contract.Invalid(issues) => {
      println(
        "{\"status\":\"invalid\",\"issues\":" +
        contract_issues_json(issues) +
        "}",
      )
      set_exit_code(2)
    }
  }
}
