import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const projectRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));
const modulePrefix = 'bzhangui/hooklab/hooklab/';
const packages = [
  ['crypto', 95],
  ['providers', 75],
  ['contract', 75],
  ['outbound', 80],
  ['delivery', 80],
  ['engine', 80],
  ['config', 75],
  ['gateway', 70],
  ['transform', 60],
];
const overallMinimum = 80;

export function parseCoverageSummary(output) {
  const totals = [...output.matchAll(/^Total:\s*(\d+)\/(\d+)\s*$/gm)];
  if (totals.length !== 1) throw new Error('Expected exactly one package coverage total');
  const covered = Number(totals[0][1]);
  const total = Number(totals[0][2]);
  if (total === 0 || covered > total) throw new Error('Invalid package coverage total');
  return {covered, total};
}

export function meetsCoverageFloor({covered, total}, minimumPercent) {
  return covered * 100 >= total * minimumPercent;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let allCovered = 0;
  let allTotal = 0;
  for (const [name, floor] of packages) {
    const result = spawnSync(
      'moon',
      ['coverage', 'analyze', '-p', modulePrefix + name, '--', '-f', 'summary'],
      {cwd: projectRoot, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024},
    );
    if (result.error || result.status !== 0) {
      console.error(result.stderr || result.error?.message || `${name}: coverage command failed`);
      process.exitCode = 1;
      break;
    }
    let counts;
    try {
      counts = parseCoverageSummary(result.stdout);
    } catch (error) {
      console.error(`${name}: ${error.message}`);
      process.exitCode = 1;
      break;
    }
    const percent = (100 * counts.covered / counts.total).toFixed(1);
    console.log(`${name}: ${counts.covered}/${counts.total} (${percent}%; floor ${floor}%)`);
    if (!meetsCoverageFloor(counts, floor)) process.exitCode = 1;
    allCovered += counts.covered;
    allTotal += counts.total;
  }
  if (allTotal > 0) {
    const percent = (100 * allCovered / allTotal).toFixed(1);
    console.log(`Selected MoonBit core: ${allCovered}/${allTotal} (${percent}%; floor ${overallMinimum}%)`);
    if (!meetsCoverageFloor({covered: allCovered, total: allTotal}, overallMinimum)) {
      process.exitCode = 1;
    }
  }
}
