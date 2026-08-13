///|
test "report escapes hostile diagnostic content" {
  let result : @pipeline.ProcessingResult = @pipeline.Rejected({
    code: @core.InvalidPayload,
    stage: @core.Input,
    message: "<script>alert(\"x\")</script>\u0001",
    suggestion: "check & retry",
  })
  let json = result_json(result)
  let html = result_html(result)
  inspect(json.contains("\\\"x\\\""), content="true")
  inspect(json.contains("\\u0001"), content="true")
  inspect(html.contains("<script>"), content="false")
  inspect(html.contains("&lt;script&gt;"), content="true")
  inspect(html.contains("check &amp; retry"), content="true")
}
