const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, chromiumSandbox: false });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    async function open() {
      await page.goto('http://127.0.0.1:8082/?page=tools-chat&state=approval');
      await page.locator('flutter-view').waitFor();
      const enable = page.getByRole('button', { name: 'Enable accessibility' });
      await enable.waitFor();
      await enable.dispatchEvent('click');
    }
    await open();
    const approve = page.getByRole('button', { name: 'Approve', exact: true });
    await approve.waitFor();
    await approve.focus();
    await page.keyboard.press('Enter');
    await page.locator('span').filter({ hasText: /^Approved fixture action$/ }).waitFor();
    const desktop = await page.locator('body').ariaSnapshot();
    await page.screenshot({ path: path.join(__dirname, 'approval-keyboard-desktop.png') });
    await page.setViewportSize({ width: 390, height: 844 });
    await open();
    await page.getByRole('button', { name: 'Deny', exact: true }).waitFor();
    await page.screenshot({ path: path.join(__dirname, 'approval-mobile-viewport.png') });
    await page.getByRole('button', { name: 'Deny', exact: true }).click();
    await page.locator('span').filter({ hasText: /^Denied fixture action$/ }).waitFor();
    const mobile = await page.locator('body').ariaSnapshot();
    const result = {
      browser: browser.version(),
      desktopViewport: { width: 1280, height: 900 },
      mobileViewport: { width: 390, height: 844 },
      keyboardApproval: true,
      pointerDenial: true,
      errors,
      desktop,
      mobile,
      note: 'Offline fixture callbacks only; mobile viewport is not device qualification. Flutter semantics activated programmatically.',
    };
    fs.writeFileSync(path.join(__dirname, 'approval-smoke.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result));
    if (errors.length) process.exitCode = 1;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
