///|
extern "js" fn read_text_file(path : String) -> String? =
  #| function(path) {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return fs.readFileSync(path, "utf8");
  #|   } catch (_) {
  #|     return null;
  #|   }
  #| }

///|
extern "js" fn write_text_file(path : String, content : String) -> Bool =
  #| function(path, content) {
  #|   try {
  #|     const fs = require("node:fs");
  #|     fs.writeFileSync(path, content, "utf8");
  #|     return true;
  #|   } catch (_) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn post_webhook(url : String, body : String) -> Unit =
  #| function(url, body) {
  #|   const retryable = status => status === 408 || status === 429 || status >= 500;
  #|   const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  #|   (async () => {
  #|     let last = "delivery failed";
  #|     for (let attempt = 1; attempt <= 5; attempt++) {
  #|       try {
  #|         const response = await fetch(url, {
  #|           method: "POST",
  #|           headers: {"content-type": "application/json", "x-hooklab-replay": "1"},
  #|           body,
  #|           signal: AbortSignal.timeout(15000)
  #|         });
  #|         const text = await response.text();
  #|         console.log(JSON.stringify({attempt, status: response.status, ok: response.ok, body: text}));
  #|         if (response.ok) return;
  #|         last = `HTTP ${response.status}`;
  #|         if (!retryable(response.status)) break;
  #|       } catch (error) {
  #|         last = String(error);
  #|         console.error(JSON.stringify({attempt, error: last}));
  #|       }
  #|       if (attempt < 5) await sleep(Math.min(1000 * 2 ** (attempt - 1), 60000));
  #|     }
  #|     console.error(JSON.stringify({dead_letter: true, reason: last}));
  #|     process.exitCode = 2;
  #|   })();
  #| }

///|
extern "js" fn set_exit_code(code : Int) -> Unit =
  #| function(code) {
  #|   if (typeof process !== "undefined") process.exitCode = code;
  #| }
