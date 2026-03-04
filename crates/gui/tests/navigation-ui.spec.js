import { test, expect } from '@playwright/test';
const appUrl = 'http://127.0.0.1:4173';

function getNavInvocations(browserPage) {
  return browserPage.evaluate(() => {
    const invocations = window.__TAURI_INTERNALS__?.invocations || [];
    return invocations.filter((entry) => entry.cmd === 'navigate_to');
  });
}

test.describe('Address bar UI navigation', () => {
  test('submits typed URL via Enter and Go button', async ({ page }) => {
    await page.addInitScript(() => {
      window.__TAURI_INTERNALS__ = {
        invocations: [],
        invoke: (cmd, args) => {
          window.__TAURI_INTERNALS__.invocations.push({ cmd, args });
          return Promise.resolve(null);
        },
        transformCallback: (callback) => callback,
        convertFileSrc: (value) => value,
        metadata: {},
      };
      window.isTauri = true;
    });

    await page.goto(appUrl, { waitUntil: 'domcontentloaded' });

    const addressInput = page.getByPlaceholder('Search or enter address');
    const goButton = page.getByRole('button', { name: 'Go' });

    await addressInput.waitFor({ state: 'visible' });
    await addressInput.fill('https://google.com');
    await addressInput.press('Enter');

    let navigateTargets = await getNavInvocations(page);
    expect(
      navigateTargets.some((entry) => entry.args?.request?.url === 'https://google.com'),
    ).toBe(true);

    await addressInput.fill('https://duckduckgo.com');
    await goButton.click();

    navigateTargets = await getNavInvocations(page);
    expect(
      navigateTargets.some((entry) => entry.args?.request?.url === 'https://duckduckgo.com'),
    ).toBe(true);
  });
});
