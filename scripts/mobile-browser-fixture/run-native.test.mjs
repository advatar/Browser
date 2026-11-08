import test from 'node:test';
import assert from 'node:assert/strict';
import { qualificationPassed, scenarios, testEnvironment, validateDestination } from './run-native.mjs';
import { startFixture } from './server.mjs';

test('native runner rejects empty, skipped, failed and unknown result schemas', () => {
  const passed = { result: 'Passed', totalTestCount: 1, passedTests: 1, failedTests: 0, skippedTests: 0 };
  assert.equal(qualificationPassed(passed), true);
  for (const summary of [null, {}, { ...passed, totalTestCount: 0 }, { ...passed, skippedTests: 1 },
    { ...passed, failedTests: 1 }, { ...passed, result: 'Failed' }, { ...passed, expectedFailures: 1 },
    { ...passed, totalTestCount: 5 }, { ...passed, skippedTests: undefined }]) {
    assert.equal(qualificationPassed(summary), false);
  }
});

test('native runner requires exact iOS destination and a reachable physical-device host', () => {
  assert.deepEqual(validateDestination('platform=iOS Simulator,id=ABC-123', '127.0.0.1'), { device: false });
  assert.deepEqual(validateDestination('platform=iOS,id=ABC-123', '192.168.2.20'), { device: true });
  for (const host of ['127.0.0.1', 'localhost', '::1', '0.0.0.0', '::']) {
    assert.throws(() => validateDestination('platform=iOS,id=ABC-123', host));
  }
  for (const destination of ['', 'platform=macOS', 'platform=iOS,name=Phone', undefined]) {
    assert.throws(() => validateDestination(destination, '127.0.0.1'));
  }
});

test('credential stays in runner environment and separate read-only oracle', async t => {
  const fixture = await startFixture();
  t.after(() => fixture.close());
  const env = testEnvironment({ KEEP: 'yes', TEST_RUNNER_BROWSER_OLD: 'stale' }, fixture);
  assert.equal(env.KEEP, 'yes');
  assert.equal(env.TEST_RUNNER_BROWSER_OLD, undefined);
  assert.equal(env.TEST_RUNNER_BROWSER_FIXTURE_ORACLE_TOKEN, fixture.oracleToken);
  assert.equal(env.TEST_RUNNER_BROWSER_NATIVE_QUALIFICATION, '1');
  assert.equal(env.TEST_RUNNER_BROWSER_FIXTURE_URL.includes(fixture.oracleToken), false);
  for (const path of ['/sources/one', '/sources/two', '/drafts/alpha/draft-a', '/client.js']) {
    assert.equal((await (await fetch(fixture.url + path)).text()).includes(fixture.oracleToken), false);
  }
  assert.equal((await fetch(fixture.url + '/oracle')).status, 401);
  const headers = { Authorization: `Bearer ${fixture.oracleToken}` };
  assert.equal((await fetch(fixture.url + '/oracle', { method: 'POST', headers })).status, 405);
  assert.equal((await fetch(fixture.url + '/oracle', { headers })).status, 200);
  assert.equal(scenarios.length, 5);
  assert.deepEqual(scenarios.filter(s => s.fault).map(s => s.fault), ['autosave', 'submit']);
});
