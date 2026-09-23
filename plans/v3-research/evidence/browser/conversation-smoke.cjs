const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

async function waitForAccessibleText(page, expected) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    if ((await page.locator('body').ariaSnapshot()).includes(expected)) return;
    await page.waitForTimeout(50);
  }
  throw new Error(`Answer missing from accessibility tree: ${expected}`);
}

(async () => {
  const browser = await chromium.launch({ headless: true, chromiumSandbox: false });
  const results = [];
  function saveEvidence(passed, failure) {
    const root = path.resolve(__dirname, '../../../..');
    const hashes = {};
    for (const file of ['examples/flutter_chat/build/web/main.dart.js', 'examples/flutter_chat/lib/pages/conversation_page.dart', 'examples/remote_backend/js/server.mjs', 'examples/remote_backend/js/package-lock.json']) {
      hashes[file] = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex');
    }
    const output = { capturedAt: new Date().toISOString(), browser: browser.version(), passed, failure, hashes, results,
      limitations: 'Scripted local model checks actual tool execution/result and denial; remote text uses pinned JavaScript AI SDK server. No live provider, persisted reload, remote tool execution, native device, or screen reader qualification. Semantics activated programmatically.' };
    fs.writeFileSync(path.join(__dirname, 'conversation-smoke.json'), JSON.stringify(output, null, 2) + '\n');
    return output;
  }
  try {
    for (const scenario of [
      { route: 'conversation', action: 'Approve', keyboard: true, expected: 'Tool result: deleted /tmp/example', width: 1280, height: 900 },
      { route: 'conversation', action: 'Deny', keyboard: false, expected: 'Tool denied; no local action ran.', width: 390, height: 844 },
      { route: 'remote', expected: 'Hello from the pinned AI SDK backend.', width: 1280, height: 900 },
      { route: 'remote', prompt: 'Request approval', action: 'Approve', expected: 'The scripted tool call was approved and resumed.', width: 1280, height: 900 },
      { route: 'remote', prompt: 'Request approval', action: 'Deny', expected: 'The scripted tool call was denied and resumed safely.', width: 390, height: 844 },
    ]) {
      const page = await browser.newPage({ viewport: { width: scenario.width, height: scenario.height } });
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => {
        if (message.type() === 'error') errors.push(message.text());
      });
      await page.goto(`http://127.0.0.1:8083/#/${scenario.route}`);
      await page.locator('flutter-view').waitFor();
      await page.getByRole('button', { name: 'Enable accessibility' }).dispatchEvent('click');
      const input = page.getByRole('textbox', { name: 'Message…', exact: true });
      await input.click();
      const prompt = scenario.prompt || 'Run the example';
      await input.pressSequentially(prompt, { delay: 20 });
      if (await input.inputValue() !== prompt) throw new Error('Composer input missing');
      await page.getByRole('button', { name: 'Send message', exact: true }).click();
      let pending;
      if (scenario.action) {
        const action = page.getByRole('button', { name: scenario.action, exact: true });
        await action.waitFor();
        pending = await page.locator('body').ariaSnapshot();
        if (scenario.keyboard) {
          await action.focus();
          await page.keyboard.press('Enter');
        } else {
          await action.click();
        }
      }
      await waitForAccessibleText(page, scenario.expected);
      const composer = page.getByRole('textbox', { name: 'Message…', exact: true });
      if (!await composer.isEnabled()) throw new Error('Composer did not return to idle');
      const assistantRows = await page.getByRole('group', { name: 'Assistant message', exact: true }).count();
      if (assistantRows !== 1) throw new Error(`Expected one assistant row, found ${assistantRows}`);
      const screenshot = scenario.route === 'remote' && scenario.action
        ? `conversation-remote-${scenario.action}.png`
        : `conversation-${scenario.action || scenario.route}.png`;
      await page.screenshot({ path: path.join(__dirname, screenshot) });
      results.push({ ...scenario, pending, final: await page.locator('body').ariaSnapshot(), errors, screenshot });
      await page.close();
      if (errors.length) throw new Error(errors.join('\n'));
    }
    console.log(JSON.stringify(saveEvidence(true)));
  } catch (error) {
    saveEvidence(false, String(error));
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
