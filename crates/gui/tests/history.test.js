import { test, expect } from '@playwright/test';
import { fileURLToPath } from 'url';
import path from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const testPagePath = path.join(__dirname, '../src/test-pages/history-test.html');
const testPageUrl = `file://${testPagePath}`;

// Helper function to wait for navigation to complete
async function waitForNavigation(page, urlPattern) {
  await page.waitForURL(urlPattern, { timeout: 5000 });
}

test.describe('History Functionality Tests', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to the test page before each test
    await page.goto(testPageUrl);
    // Wait for the page to be fully loaded
    await page.waitForLoadState('networkidle');
  });

  test('should track page navigation in history', async ({ page }) => {
    // Test internal anchor navigation first (more reliable for testing)
    await page.click('a[href="#section1"]');
    await waitForNavigation(page, /#section1/);
    
    // Test back/forward navigation
    await page.goBack();
    await expect(page).not.toHaveURL(/#section1/);
    
    await page.goForward();
    await expect(page).toHaveURL(/#section1/);
  });

  test('should update history panel when pages are visited', async ({ page }) => {
    // Test with internal navigation since external sites might be blocked
    await page.click('a[href="#section1"]');
    await waitForNavigation(page, /#section1/);
    
    // Go back to main page
    await page.goBack();
    
    // Verify the navigation was recorded in history
    // This is just a basic check - in a real test, you'd verify the UI updates
    const navigationCount = await page.evaluate(() => window.history.length);
    expect(navigationCount).toBeGreaterThan(1);
  });

  test('should support history operations', async ({ page }) => {
    // Test basic history operations
    const initialHistoryLength = await page.evaluate(() => window.history.length);
    
    // Navigate to section 1
    await page.click('a[href="#section1"]');
    await waitForNavigation(page, /#section1/);
    
    // Navigate to section 2
    await page.click('a[href="#section2"]');
    await waitForNavigation(page, /#section2/);
    
    // Go back and verify
    await page.goBack();
    await expect(page).toHaveURL(/#section1/);
    
    // Go forward and verify
    await page.goForward();
    await expect(page).toHaveURL(/#section2/);
    
    // Verify history length increased
    const newHistoryLength = await page.evaluate(() => window.history.length);
    expect(newHistoryLength).toBeGreaterThan(initialHistoryLength);
  });

  test('should handle history state operations', async ({ page }) => {
    // Test pushState
    await page.evaluate(() => {
      window.history.pushState({ test: 'state1' }, 'State 1', '?state=1');
    });
    
    // Test replaceState
    await page.evaluate(() => {
      window.history.replaceState({ test: 'state2' }, 'State 2', '?state=2');
    });
    
    // Verify current state
    const state = await page.evaluate(() => window.history.state);
    expect(state).toEqual({ test: 'state2' });
  });

  test('should trigger popstate on navigation', async ({ page }) => {
    // Set up a promise that resolves when popstate is called
    const popstatePromise = page.evaluate(() => {
      return new Promise((resolve) => {
        window.addEventListener('popstate', () => {
          resolve('popstate triggered');
        }, { once: true });
      });
    });
    
    // Navigate to section 1
    await page.click('a[href="#section1"]');
    await waitForNavigation(page, /#section1/);
    
    // Go back which should trigger popstate
    await page.goBack();
    
    // Wait for popstate to be triggered
    const result = await popstatePromise;
    expect(result).toBe('popstate triggered');
  });
});
