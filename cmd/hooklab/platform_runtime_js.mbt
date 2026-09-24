///|
/// PostgreSQL platform adapter. Run from the repository root after npm ci.
extern "js" fn run_platform_runtime(
  port : Int,
  plan : (String, String, String, String, String) -> String,
  sign : (String, Int64, String, String, String, String) -> String,
  decide : (Int, Int, String, String) -> String,
  validate : (String, String, String, String, Bool) -> String,
) -> Unit =
  #| function(port, plan, sign, decide, validate) {
  #|   const path = require('node:path');
  #|   const root = process.env.HOOKLAB_PLATFORM_ROOT || process.cwd();
  #|   const {startPlatform} = require(path.join(root, 'platform', 'server.cjs'));
  #|   startPlatform({port, callbacks: {plan, sign, decide, validate}}).then(runtime => {
  #|     console.log('HookLab platform listening on ' + (process.env.HOOKLAB_BIND_HOST || '127.0.0.1') + ':' + port);
  #|     const shutdown = () => runtime.close().then(() => process.exit(0)).catch(error => {console.error(error); process.exit(1);});
  #|     process.once('SIGINT', shutdown);
  #|     process.once('SIGTERM', shutdown);
  #|   }).catch(error => { console.error('HookLab platform startup failed:', error); process.exitCode = 1; });
  #| }
