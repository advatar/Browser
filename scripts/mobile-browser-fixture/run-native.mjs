// Private local orchestration for the existing fixture; never deploys or publishes.
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmod, mkdtemp, readFile, readdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { startFixture } from './server.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const project = resolve(root, 'swift/dBrowser/dBrowser.xcodeproj');
const packagePaths = [
  resolve(root, '../Packages/UniversalInteractionKit'),
  resolve(root, '../Packages/UniversalInteractionKit/Packages/UniversalA2UI'),
  resolve(root, '../ZeroK/zk-llm-gateway/zk-llm-gateway-swift-sdk')
];
export const scenarios = Object.freeze([
  { method: 'testNavigationAndAutosaveBeforeSubmit', fault: null },
  { method: 'testStaleDocumentRefusal', fault: null },
  { method: 'testNavigationInvalidatesApprovalAndDispatch', fault: null },
  { method: 'testLostAutosaveAcknowledgement', fault: 'autosave' },
  { method: 'testLostSubmitAcknowledgement', fault: 'submit' }
]);

export function validateDestination(destination, host) {
  if (!/^platform=iOS(?: Simulator)?,id=[A-Za-z0-9-]+$/.test(destination ?? '')) {
    throw new Error('Supply an exact destination: platform=iOS Simulator,id=<UDID> or platform=iOS,id=<UDID>.');
  }
  const device = destination.startsWith('platform=iOS,');
  if (device && ['127.0.0.1', 'localhost', '::1', '0.0.0.0', '::'].includes(host)) {
    throw new Error('A physical iPhone requires --host with this Mac’s reachable LAN address, not loopback/wildcard.');
  }
  return { device };
}

export function qualificationPassed(summary) {
  // Fail closed if xcresulttool changes its schema or the filter runs zero tests.
  return summary?.result === 'Passed' && summary.totalTestCount === 1
    && summary.passedTests === 1 && summary.failedTests === 0 && summary.skippedTests === 0
    && (summary.expectedFailures ?? 0) === 0;
}

export function testEnvironment(base, fixture) {
  // Never inherit an earlier qualification's test-runner credentials/configuration.
  const env = Object.fromEntries(Object.entries(base).filter(([key]) => !key.startsWith('TEST_RUNNER_BROWSER_')));
  return { ...env,
    TEST_RUNNER_BROWSER_NATIVE_QUALIFICATION: '1',
    TEST_RUNNER_BROWSER_FIXTURE_URL: fixture.url,
    TEST_RUNNER_BROWSER_FIXTURE_ORACLE_TOKEN: fixture.oracleToken
  };
}

function capture(command, args, cwd = root) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`Required command failed: ${command} ${args.join(' ')}`);
  return result.stdout.trim();
}

async function sourceIdentity() {
  const changes = capture('git', ['diff', 'HEAD', '--binary']);
  const untracked = capture('git', ['ls-files', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean);
  const untrackedHashes = {};
  for (const name of untracked) untrackedHashes[name] = createHash('sha256').update(await readFile(resolve(root, name))).digest('hex');
  return {
    commit: capture('git', ['rev-parse', 'HEAD']),
    status: capture('git', ['status', '--porcelain']),
    trackedDiffSHA256: createHash('sha256').update(changes).digest('hex'), untrackedHashes
  };
}

async function runLogged(command, args, log, { env = process.env, secret = '' } = {}) {
  // Keep raw output private while running; publish only a redacted local log.
  // xcresult bundles also remain in this mode-0700 directory, never uploaded.
  const chunks = [];
  const exitCode = await new Promise((resolveExit, reject) => {
    const child = spawn(command, args, { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.on('data', chunk => chunks.push(chunk));
    child.stderr.on('data', chunk => chunks.push(chunk));
    child.once('error', reject);
    child.once('close', code => resolveExit(code));
  });
  let output = Buffer.concat(chunks).toString('utf8');
  if (secret) output = output.split(secret).join('[REDACTED]');
  await writeFile(log, output, { mode: 0o600 });
  if (exitCode !== 0) throw new Error(`${command} failed (${exitCode}); inspect private log ${log}`);
}

async function main() {
  const { values } = parseArgs({ options: {
    destination: { type: 'string' }, host: { type: 'string', default: '127.0.0.1' },
    team: { type: 'string' }, preflight: { type: 'boolean', default: false }
  }});
  if (process.platform !== 'darwin') throw new Error('Native qualification UNEXECUTED: macOS with compatible Xcode/iOS SDK is required.');
  const xcode = capture('xcodebuild', ['-version']);
  const sdks = capture('xcodebuild', ['-showsdks']);
  const missing = packagePaths.filter(path => !existsSync(resolve(path, 'Package.swift')));
  if (missing.length) throw new Error(`Missing required local Swift packages:\n${missing.join('\n')}`);
  if (values.preflight) {
    console.log(xcode, '\n', sdks);
    console.log(capture('xcodebuild', ['-list', '-project', project]));
    console.log(capture('xcodebuild', ['-showdestinations', '-project', project, '-scheme', 'NativeMobileBrowser']));
    return;
  }
  const { device } = validateDestination(values.destination, values.host);
  const output = await mkdtemp(resolve(tmpdir(), 'browser-native-'));
  await chmod(output, 0o700);
  console.log(`Private native evidence directory: ${output}`);
  const derived = resolve(output, 'DerivedData');
  const source = await sourceIdentity();
  const metadata = {
    startedAt: new Date().toISOString(), status: 'building', source, xcode, sdks,
    macOS: capture('sw_vers', []), node: process.version,
    destination: values.destination, fixtureHost: values.host, physicalDevice: device,
    packages: packagePaths.map(path => ({ path, commit: capture('git', ['rev-parse', 'HEAD'], path), status: capture('git', ['status', '--porcelain'], path) })),
    scenarios: [], rawResultsArePrivate: true
  };
  const evidence = resolve(output, 'qualification.json');
  const save = () => writeFile(evidence, JSON.stringify(metadata, null, 2) + '\n', { mode: 0o600 });
  await save();
  try {
    const signing = device ? (values.team ? [`DEVELOPMENT_TEAM=${values.team}`] : []) : ['CODE_SIGNING_ALLOWED=NO'];
    await runLogged('xcodebuild', ['build-for-testing', '-project', project, '-scheme', 'NativeMobileBrowser',
      '-destination', values.destination, '-derivedDataPath', derived, ...signing], resolve(output, 'build.log'));
    const products = resolve(derived, 'Build/Products');
    const manifests = (await readdir(products)).filter(name => name.endsWith('.xctestrun'));
    if (manifests.length !== 1) throw new Error('Expected exactly one built xctestrun manifest; inspect the private build output.');
    for (const scenario of scenarios) {
      console.log(`Running ${scenario.method} (${device ? 'physical device' : 'simulator'})`);
      const fixture = await startFixture({ host: values.host, port: 0, dropResponseAfterCommit: scenario.fault });
      const resultBundle = resolve(output, `${scenario.method}.xcresult`);
      const record = { ...scenario, fixtureId: fixture.fixtureId, fixtureURL: fixture.url, resultBundle, status: 'running' };
      metadata.scenarios.push(record);
      await save();
      try {
        await runLogged('xcodebuild', ['test-without-building', '-xctestrun', resolve(products, manifests[0]),
          '-destination', values.destination, '-parallel-testing-enabled', 'NO',
          '-only-testing:dBrowserTests/NativeMobileBrowserTests/' + scenario.method,
          '-resultBundlePath', resultBundle], resolve(output, `${scenario.method}.log`), {
            env: testEnvironment(process.env, fixture), secret: fixture.oracleToken
          });
        const summary = JSON.parse(capture('xcrun', ['xcresulttool', 'get', 'test-results', 'summary', '--path', resultBundle]));
        record.summary = summary;
        if (!qualificationPassed(summary)) throw new Error('Expected one passing native test with zero failures/skips; no qualification claimed.');
        // Second host-side readback is independent of the hosted test's URLSession.
        const response = await fetch(`${fixture.url}/oracle`, { headers: { Authorization: `Bearer ${fixture.oracleToken}` }, redirect: 'error' });
        if (!response.ok) throw new Error('Host oracle readback failed.');
        const ledger = await response.json();
        await writeFile(resolve(output, `${scenario.method}-oracle.json`), JSON.stringify(ledger, null, 2) + '\n', { mode: 0o600 });
        record.status = 'passed';
      } catch (error) {
        record.status = 'failed';
        throw error;
      } finally {
        await fixture.close();
        await save();
      }
    }
    if (JSON.stringify(await sourceIdentity()) !== JSON.stringify(source)) throw new Error('Source changed during qualification; results are not bound to one tree.');
    metadata.status = 'passed';
    console.log(`Five native scenarios passed. Evidence: ${evidence}`);
  } catch (error) {
    metadata.status = 'failed';
    throw error;
  } finally {
    metadata.finishedAt = new Date().toISOString();
    await save();
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
