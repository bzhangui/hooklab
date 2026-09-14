const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

function signalProcessTree(child, signal) {
  if (!child.pid) return;
  if (process.platform !== "win32") {
    try {
      process.kill(-child.pid, signal);
      return;
    } catch (_) {}
  }
  try {
    child.kill(signal);
  } catch (_) {}
}

function waitForExit(child, timeoutMs) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve(true);
  }
  return new Promise(resolve => {
    const onExit = () => finish(true);
    const timer = setTimeout(() => finish(false), timeoutMs);
    function finish(exited) {
      clearTimeout(timer);
      child.off("exit", onExit);
      resolve(exited);
    }
    child.once("exit", onExit);
  });
}

export async function stopChild(child) {
  if (!child.pid) return;
  signalProcessTree(child, "SIGTERM");
  const exited = await waitForExit(child, 1500);
  if (!exited || process.platform !== "win32") {
    signalProcessTree(child, "SIGKILL");
    await waitForExit(child, 1500);
  }
  await pause(50);
}
