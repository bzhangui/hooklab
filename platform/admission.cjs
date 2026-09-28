'use strict';

function parseMaxInflight(value) {
  const text = value || '0';
  if (!/^(0|[1-9][0-9]{0,4})$/.test(text)) throw new Error('Invalid HOOKLAB_MAX_INFLIGHT_REQUESTS');
  return Number(text);
}

// A local overload fuse, not a distributed tenant quota or ingress rate limiter.
function createAdmission(max, reject) {
  const stats = {active: 0, rejected: 0};
  const admit = response => {
    if (max > 0 && stats.active >= max) {
      stats.rejected++;
      reject(response);
      return false;
    }
    stats.active++;
    response.once('close', () => { stats.active--; });
    return true;
  };
  admit.stats = stats;
  return admit;
}

module.exports = {parseMaxInflight, createAdmission};
