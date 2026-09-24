///|
test "structured event schema checks required and nested types" {
  let schema =
    #|{"type":"object","required":["orderId"],"properties":{"orderId":{"type":"integer"},"lines":{"type":"array","items":{"type":"string"}}},"additionalProperties":false}
  let valid =
    #|{"specversion":"1.0","id":"e1","source":"/orders","type":"order.created","data":{"orderId":42,"lines":["a"]}}
  inspect(
    validate_event_json(
      valid, "application/cloudevents+json", "order.created", schema, true,
    ).length(),
    content="0",
  )
  let invalid =
    #|{"specversion":"1.0","id":"e2","source":"/orders","type":"order.created","data":{"lines":[2],"extra":true}}
  let issues = validate_event_json(
    invalid, "application/cloudevents+json", "order.created", schema, true,
  )
  inspect(issues.length(), content="3")
  inspect(issues[0].code, content="required")
}

///|
test "invalid structured event rejects before schema" {
  let issues = validate_event_json(
    "{\"specversion\":\"0.3\"}", "application/cloudevents+json", "order.created",
    "", true,
  )
  inspect(issues[0].code, content="invalid_cloudevent")
}

///|
test "schema compatibility preserves widening and rejects narrowing" {
  let baseline =
    #|{"type":"object","required":["id"],"properties":{"id":{"type":"integer"},"items":{"type":"array","items":{"type":"string"}}},"additionalProperties":false}
  inspect(
    schema_compatible_json(
      baseline,
      (
        #|{"type":"object","required":["id"],"properties":{"id":{"type":"number"},"items":{"type":"array","items":{}},"note":{"type":"string"}},"additionalProperties":false}
      ),
    ),
    content="true",
  )
  inspect(
    schema_compatible_json(
      baseline,
      (
        #|{"type":"object","required":["id","items"],"properties":{"id":{"type":"integer"},"items":{"type":"array","items":{"type":"string"}}},"additionalProperties":false}
      ),
    ),
    content="false",
  )
  inspect(
    schema_compatible_json(
      baseline,
      (
        #|{"type":"object","required":["id"],"properties":{"id":{"type":"integer"}},"additionalProperties":false}
      ),
    ),
    content="false",
  )
  inspect(
    schema_compatible_json(
      (
        #|{"type":"object"}
      ),
      (
        #|{"type":"object","properties":{"newField":{"type":"string"}}}
      ),
    ),
    content="false",
  )
  inspect(
    schema_compatible_json(
      (
        #|{"type":"string","enum":["a","b"]}
      ),
      (
        #|{"type":"string","enum":["a","b","c"]}
      ),
    ),
    content="true",
  )
  inspect(
    schema_compatible_json(
      (
        #|{"type":"string","enum":["a","b"]}
      ),
      (
        #|{"type":"string","enum":["a"]}
      ),
    ),
    content="false",
  )
  inspect(
    schema_compatible_json(
      (
        #|{"type":"array"}
      ),
      (
        #|{"type":"array","items":{"type":"string"}}
      ),
    ),
    content="false",
  )
  inspect(schema_compatible_json("invalid", "{}"), content="false")
}
