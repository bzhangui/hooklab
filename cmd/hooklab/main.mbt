///|
fn usage() -> Unit {
  let text =
    #|HookLab — verify, diagnose, route, and safely replay webhooks
    #|
    #|Usage:
    #|  hooklab sign <provider> <secret> <body|@file> [timestamp] [nonce]
    #|  hooklab verify <provider> <secret> <body|@file> <signature> [timestamp] [id]
    #|  hooklab inspect <provider> <secret> <body|@file> <signature> [timestamp] [id]
    #|  hooklab report <provider> <secret> <body|@file> <signature> <output.html> [timestamp] [id]
    #|  hooklab route-test <body|@file> <json.path> <expected> <target>
    #|  hooklab retry-plan [attempts]
    #|  hooklab replay <url> <body|@file>
    #|
    #|Providers: github, stripe, feishu, generic-hmac
    #|Prefix a body with @ to read UTF-8 content from a file.
  println(text)
}

///|
fn provider_from_string(value : String) -> @core.Provider? {
  match @core.ascii_lower(value) {
    "github" => Some(@core.GitHub)
    "stripe" => Some(@core.Stripe)
    "feishu" | "lark" => Some(@core.Feishu)
    "generic" | "generic-hmac" => Some(@core.GenericHmac)
    _ => None
  }
}

///|
fn body_from_arg(value : String) -> String? {
  if value.has_prefix("@") {
    read_text_file(value[1:].to_owned())
  } else {
    Some(value)
  }
}

///|
fn current_seconds() -> Int64 {
  @env.now().reinterpret_as_int64() / 1000L
}

///|
fn signature_for(
  provider : @core.Provider,
  secret : String,
  body : String,
  timestamp : String,
  nonce : String,
) -> String {
  match provider {
    @core.GitHub => "sha256=" + @crypto.hmac_sha256_hex(secret, body)
    @core.Stripe => {
      let value = @crypto.hmac_sha256_hex(secret, timestamp + "." + body)
      "t=" + timestamp + ",v1=" + value
    }
    @core.Feishu => @crypto.sha256_hex(timestamp + nonce + secret + body)
    @core.GenericHmac =>
      "sha256=" + @crypto.hmac_sha256_hex(secret, timestamp + "." + body)
  }
}

///|
fn request_for(
  provider : @core.Provider,
  body : String,
  signature : String,
  timestamp : String,
  id : String,
) -> @core.WebhookRequest {
  let headers : Array[@core.Header] = match provider {
    @core.GitHub =>
      [
        @core.header("x-hub-signature-256", signature),
        @core.header("x-github-event", "hooklab.inspect"),
        @core.header("x-github-delivery", id),
      ]
    @core.Stripe =>
      [
        @core.header("stripe-signature", signature),
        @core.header("x-hooklab-delivery-id", id),
      ]
    @core.Feishu =>
      [
        @core.header("x-lark-signature", signature),
        @core.header("x-lark-request-timestamp", timestamp),
        @core.header("x-lark-request-nonce", id),
      ]
    @core.GenericHmac =>
      [
        @core.header("x-webhook-signature", signature),
        @core.header("x-webhook-timestamp", timestamp),
        @core.header("x-webhook-id", id),
      ]
  }
  { provider, headers, body, received_at: current_seconds() }
}

///|
fn verification_result_json(result : @core.VerificationResult) -> String {
  match result {
    @core.Verified(event) =>
      "{\"status\":\"verified\",\"provider\":\"" +
      @core.provider_name(event.provider) +
      "\",\"event_type\":\"" +
      event.event_type +
      "\"}"
    @core.Rejected(failure) =>
      "{\"status\":\"rejected\",\"code\":\"" +
      @core.failure_code_name(failure.code) +
      "\",\"stage\":\"" +
      @core.stage_name(failure.stage) +
      "\",\"message\":\"" +
      failure.message +
      "\"}"
  }
}

///|
fn do_sign(args : Array[String]) -> Unit {
  guard args.length() >= 4 else {
    usage()
    set_exit_code(1)
    return
  }
  guard provider_from_string(args[1]) is Some(provider) else {
    println("Unknown provider: " + args[1])
    set_exit_code(1)
    return
  }
  guard body_from_arg(args[3]) is Some(body) else {
    println("Unable to read body file.")
    set_exit_code(1)
    return
  }
  let timestamp = if args.length() > 4 {
    args[4]
  } else {
    current_seconds().to_string()
  }
  let nonce = if args.length() > 5 { args[5] } else { "hooklab-nonce" }
  println(signature_for(provider, args[2], body, timestamp, nonce))
}

///|
fn parse_verification(
  args : Array[String],
  report_mode : Bool,
) -> (@core.WebhookRequest, String, String)? {
  let minimum = if report_mode { 6 } else { 5 }
  guard args.length() >= minimum else { return None }
  guard provider_from_string(args[1]) is Some(provider) else { return None }
  guard body_from_arg(args[3]) is Some(body) else { return None }
  let extra_start = if report_mode { 6 } else { 5 }
  let timestamp = if args.length() > extra_start {
    args[extra_start]
  } else {
    current_seconds().to_string()
  }
  let id = if args.length() > extra_start + 1 {
    args[extra_start + 1]
  } else {
    "hooklab-cli"
  }
  let signature = args[4]
  Some(
    (
      request_for(provider, body, signature, timestamp, id),
      args[2],
      if report_mode {
        args[5]
      } else {
        ""
      },
    ),
  )
}

///|
fn do_verify(args : Array[String]) -> Unit {
  guard parse_verification(args, false) is Some((request, secret, _)) else {
    usage()
    set_exit_code(1)
    return
  }
  let result = providers_verify(request, secret)
  println(verification_result_json(result))
  if result is @core.Rejected(_) {
    set_exit_code(2)
  }
}

///|
fn providers_verify(
  request : @core.WebhookRequest,
  secret : String,
) -> @core.VerificationResult {
  @providers.verify(request, secret)
}

///|
fn do_report(args : Array[String]) -> Unit {
  guard parse_verification(args, true) is Some((request, secret, output)) else {
    usage()
    set_exit_code(1)
    return
  }
  let store = @engine.MemoryIdempotencyStore::new()
  let result = @pipeline.process(request, secret, store, [])
  if write_text_file(output, @report.result_html(result)) {
    println("Wrote offline diagnosis: " + output)
  } else {
    println("Unable to write report: " + output)
    set_exit_code(1)
  }
  if result is @pipeline.Rejected(_) {
    set_exit_code(2)
  }
}

///|
fn do_route_test(args : Array[String]) -> Unit {
  guard args.length() >= 5 else {
    usage()
    set_exit_code(1)
    return
  }
  guard body_from_arg(args[1]) is Some(body) else {
    println("Unable to read body file.")
    set_exit_code(1)
    return
  }
  let matches = @engine.route(body, [
    {
      name: "cli-rule",
      path: args[2],
      operator: @engine.Equals,
      expected: args[3],
      target: args[4],
    },
  ])
  println(
    "{\"matched\":" +
    (matches.length() > 0).to_string() +
    ",\"count\":" +
    matches.length().to_string() +
    "}",
  )
}

///|
fn do_retry_plan(args : Array[String]) -> Unit {
  let attempts = if args.length() > 1 {
    try @string.parse_int(args[1]) catch {
      _ => 5
    } noraise {
      value => value
    }
  } else {
    5
  }
  let policy : @engine.RetryPolicy = {
    max_attempts: attempts,
    initial_delay_ms: 1000L,
    multiplier: 2L,
    max_delay_ms: 60000L,
  }
  for step in @engine.retry_schedule(policy, 0L) {
    println(
      "attempt=" +
      step.attempt.to_string() +
      " delay_ms=" +
      step.delay_ms.to_string(),
    )
  }
}

///|
fn command_args(all : Array[String]) -> Array[String] {
  let commands = [
    "sign", "verify", "inspect", "report", "route-test", "retry-plan", "replay",
    "help", "--help", "-h",
  ]
  for i = 0; i < all.length(); i = i + 1 {
    if commands.contains(all[i]) {
      let result : Array[String] = []
      for j = i; j < all.length(); j = j + 1 {
        result.push(all[j])
      }
      return result
    }
  }
  []
}

///|
fn main {
  let args = command_args(@env.args())
  guard args.length() > 0 else {
    usage()
    return
  }
  match args[0] {
    "sign" => do_sign(args)
    "verify" | "inspect" => do_verify(args)
    "report" => do_report(args)
    "route-test" => do_route_test(args)
    "retry-plan" => do_retry_plan(args)
    "replay" => {
      guard args.length() >= 3 else {
        usage()
        set_exit_code(1)
        return
      }
      guard body_from_arg(args[2]) is Some(body) else {
        println("Unable to read body file.")
        set_exit_code(1)
        return
      }
      post_webhook(args[1], body)
    }
    _ => usage()
  }
}
