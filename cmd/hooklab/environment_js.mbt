///|
extern "js" fn read_environment(name : String) -> String? =
  #| function(name) {
  #|   const value = typeof process !== "undefined" ? process.env[name] : undefined;
  #|   return value === undefined || value === "" ? null : value;
  #| }
