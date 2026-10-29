#!/usr/bin/env node
// Drives the flutter_chat web build in the run's headless Chromium over CDP.
// Invoked through `vfc browser ...` / `vfc scenario ...`, which set the VFC_*
// environment. Every invocation appends the network requests to non-app
// origins, console errors and page errors it observed to events.jsonl in the
// evidence directory.
const fs = require('node:fs');
const path = require('node:path');

const WEB = `http://127.0.0.1:${process.env.VFC_WEB_PORT}`;
const CDP = `http://127.0.0.1:${process.env.VFC_CDP_PORT}`;
const EVIDENCE = process.env.VFC_EVIDENCE_DIR;
const RUN_DIR = process.env.VFC_RUN_DIR;
if (!process.env.VFC_WEB_PORT || !EVIDENCE) {
  console.error('drive.cjs: run through `vfc browser` or `vfc scenario`');
  process.exit(2);
}
const WEB_ORIGIN = new URL(WEB).origin;

const LABELS = {
  en: {
    hint: 'Message…', send: 'Send message', stop: 'Stop response', approve: 'Approve', deny: 'Deny',
    assistant: 'Assistant message', user: 'User message', retry: 'Retry', dismiss: 'Dismiss',
    toggle: 'التبديل إلى العربية',
  },
  ar: {
    hint: 'رسالة…', send: 'إرسال الرسالة', stop: 'إيقاف الاستجابة', approve: 'موافقة', deny: 'رفض',
    assistant: 'رسالة المساعد', user: 'رسالة المستخدم', retry: 'إعادة المحاولة', dismiss: 'إغلاق',
    toggle: 'Switch to English',
  },
};

function loadPlaywright() {
  // VFC_NPM_GLOBAL is `npm root -g`; the Playwright MCP server bundles a
  // usable copy there when no standalone install exists.
  const roots = [process.env.VFC_NPM_GLOBAL, path.resolve(path.dirname(process.execPath), '..', 'lib', 'node_modules')].filter(Boolean);
  const candidates = [
    process.env.PLAYWRIGHT_MODULE,
    'playwright',
    'playwright-core',
    ...roots.flatMap(root => [
      path.join(root, 'playwright'),
      path.join(root, 'playwright-core'),
      path.join(root, '@playwright/mcp/node_modules/playwright'),
      path.join(root, '@playwright/mcp/node_modules/playwright-core'),
    ]),
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      return require(require.resolve(candidate, { paths: [process.cwd(), ...roots] }));
    } catch {}
  }
  throw new Error('Playwright not found: `npm i -g playwright` or set PLAYWRIGHT_MODULE=/path/to/playwright');
}

function isWebUrl(url) {
  try { return new URL(url).origin === WEB_ORIGIN; } catch { return false; }
}

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith('--')) { positional.push(arg); continue; }
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) flags[key] = true;
    else { flags[key] = next; i++; }
  }
  return { positional, flags };
}

async function connect(command) {
  const { chromium } = loadPlaywright();
  const browser = await chromium.connectOverCDP(CDP);
  const context = browser.contexts()[0];
  const page = context.pages().find(p => isWebUrl(p.url())) || context.pages()[0] || await context.newPage();
  const events = [];
  const bodies = [];
  const log = entry => {
    const event = { at: new Date().toISOString(), command, ...entry };
    events.push(event);
    return event;
  };
  page.on('request', request => {
    if (isWebUrl(request.url())) return;
    log({ type: 'request', method: request.method(), url: request.url(), postData: request.postData() });
  });
  page.on('response', response => {
    if (isWebUrl(response.url())) return;
    const headers = response.headers();
    const entry = log({
      type: 'response', method: response.request().method(), url: response.url(), status: response.status(),
      contentType: headers['content-type'], uiMessageStream: headers['x-vercel-ai-ui-message-stream'],
    });
    if (response.request().method() === 'POST') {
      bodies.push({ entry, promise: response.text().then(body => { entry.body = body; }, error => { entry.bodyError = String(error); }) });
    }
  });
  page.on('requestfailed', request => {
    if (isWebUrl(request.url())) return;
    log({ type: 'requestfailed', method: request.method(), url: request.url(), failure: request.failure()?.errorText });
  });
  page.on('console', message => { if (message.type() === 'error') log({ type: 'console-error', text: message.text() }); });
  page.on('pageerror', error => log({ type: 'pageerror', text: error.message }));
  let finishTask;
  return {
    page,
    events,
    async finish() {
      if (finishTask) return finishTask;
      finishTask = (async () => {
        let timer;
        const timedOut = await Promise.race([
          Promise.allSettled(bodies.map(body => body.promise)).then(() => false),
          new Promise(resolve => { timer = setTimeout(() => resolve(true), 30000); }),
        ]);
        clearTimeout(timer);
        if (timedOut) {
          for (const { entry } of bodies) {
            if (entry.body === undefined && entry.bodyError === undefined) entry.bodyError = 'Response body capture exceeded 30000ms';
          }
        }
        if (events.length) {
          fs.appendFileSync(path.join(EVIDENCE, 'events.jsonl'), events.map(e => JSON.stringify(e)).join('\n') + '\n');
        }
      })();
      return finishTask;
    },
  };
}

// Flutter web renders to a canvas; the DOM accessibility tree only exists
// after its semantics placeholder is activated.
async function ensureSemantics(page) {
  await page.locator('flutter-view').waitFor({ timeout: 60000 });
  if (await page.locator('flt-semantics').count() > 0) return;
  const placeholder = page.getByRole('button', { name: 'Enable accessibility' });
  await placeholder.waitFor({ state: 'attached', timeout: 30000 });
  await placeholder.dispatchEvent('click');
  await page.locator('flt-semantics').first().waitFor({ state: 'attached', timeout: 15000 });
}

async function open(page, route = '/', { width = 1280, height = 900 } = {}) {
  await page.setViewportSize({ width: Number(width), height: Number(height) });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  // about:blank first so a hash-only change still boots a fresh app instance.
  await page.goto('about:blank');
  await page.goto(`${WEB}/#${route.startsWith('/') ? route : `/${route}`}`);
  await ensureSemantics(page);
}

const aria = page => page.locator('body').ariaSnapshot();

async function waitText(page, expected, timeout = 30000) {
  const deadline = Date.now() + Number(timeout);
  while (Date.now() < deadline) {
    if ((await aria(page)).includes(expected)) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Text never appeared in the accessibility tree: ${expected}`);
}

async function waitGone(page, text, timeout = 15000) {
  const deadline = Date.now() + Number(timeout);
  while (Date.now() < deadline) {
    if (!(await aria(page)).includes(text)) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Text still present: ${text}`);
}

async function waitForSettled(page, L, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const state = await readState(page, L);
    const stopVisible = await page.getByRole('button', { name: L.stop, exact: true }).count() > 0;
    const sendVisible = await page.getByRole('button', { name: L.send, exact: true }).count() > 0;
    if (state.composerEditable && sendVisible && !stopVisible && !state.approvalPending && state.assistantRows === 1) return state;
    await page.waitForTimeout(100);
  }
  throw new Error('Turn did not settle to one assistant message and an editable composer');
}

async function typeInto(page, locator, text) {
  await locator.click();
  // Direct DOM fill does not reliably reach Flutter's editing state; type keys.
  await locator.press('Control+A');
  await locator.pressSequentially(text, { delay: 20 });
  const value = await locator.inputValue();
  if (value !== text) throw new Error(`Textbox holds "${value}", expected "${text}"`);
}

async function send(page, text, L) {
  await typeInto(page, page.getByRole('textbox', { name: L.hint, exact: true }), text);
  await page.getByRole('button', { name: L.send, exact: true }).click();
}

async function readState(page, L) {
  const composer = page.getByRole('textbox', { name: L.hint, exact: true });
  const sendButton = page.getByRole('button', { name: L.send, exact: true });
  const present = await composer.count() > 0;
  return {
    composerPresent: present,
    composerEditable: present ? await composer.isEditable() : false,
    sendEnabled: await sendButton.count() > 0 ? await sendButton.isEnabled() : false,
    approvalPending: await page.getByRole('button', { name: L.approve, exact: true }).count() > 0,
    assistantRows: await page.getByRole('group', { name: L.assistant, exact: true }).count(),
    userRows: ((await aria(page)).match(new RegExp(`^\\s*- (?:text|group): ${L.user} `, 'gm')) || []).length,
  };
}

async function snapshot(page, name) {
  if (typeof name !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name) || name === '.' || name === '..') {
    throw new Error(`Invalid snapshot name: ${String(name)}`);
  }
  const base = path.join(EVIDENCE, name);
  fs.writeFileSync(`${base}.aria.txt`, await aria(page) + '\n');
  await page.screenshot({ path: `${base}.png` });
  return [`${base}.aria.txt`, `${base}.png`];
}

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function backendReachable() {
  const state = fs.readFileSync(path.join(RUN_DIR, 'state.env'), 'utf8');
  const port = /BACKEND_PORT=(\d+)/.exec(state)[1];
  try {
    const response = await fetch(`http://127.0.0.1:${port}/chat`, { method: 'OPTIONS', signal: AbortSignal.timeout(5000) });
    return response.status === 204;
  } catch {
    return false;
  }
}

// ── Scenarios: each runs one user path end to end and records its proof. ──

async function approvalFlow(page, step, { route, prompt, action, keyboard, expected, L = LABELS.en }) {
  await send(page, prompt, L);
  step('send', { prompt });
  const button = page.getByRole('button', { name: L[action], exact: true });
  await button.waitFor({ timeout: 30000 });
  const pending = await readState(page, L);
  step('approval pending', pending);
  check(!pending.composerEditable, 'Composer accepts edits while approval is pending');
  check(!pending.sendEnabled, 'Send is enabled while approval is pending');
  await snapshot(page, `${route}-${action}-pending`);
  if (keyboard) { await button.focus(); await page.keyboard.press('Enter'); } else await button.click();
  step(keyboard ? `${action} via keyboard` : `${action} via click`);
  await waitText(page, expected);
  const final = await waitForSettled(page, L);
  step('final', { expected, ...final });
  check(final.composerEditable, 'Composer did not return to editable state');
  check(!final.approvalPending, 'Approval card still visible');
  check(final.assistantRows === 1, `Expected one assistant message, found ${final.assistantRows}`);
}

function chatPosts(events) {
  return events.filter(e => e.type === 'response' && e.method === 'POST' && e.url.endsWith('/chat'));
}

function checkChatResponses(posts, count, resumeText) {
  check(posts.length === count, `Expected ${count} POST /chat responses, got ${posts.length}`);
  posts.forEach((post, index) => {
    check(post.status === 200, `POST /chat response ${index + 1} returned ${post.status}`);
    check(post.uiMessageStream === 'v1', `POST /chat response ${index + 1} lacks x-vercel-ai-ui-message-stream: v1`);
    check(typeof post.body === 'string' && post.body.length > 0, `POST /chat response ${index + 1} body was not captured`);
  });
  if (resumeText) check(posts[posts.length - 1].body.includes(resumeText), 'Response body lacks the scripted text');
}

const SCENARIOS = {
  'local-approve': {
    viewport: { width: 1280, height: 900 },
    async run(page, step) {
      await open(page, '/conversation', this.viewport);
      await approvalFlow(page, step, { route: 'local', prompt: 'Run the example', action: 'approve', keyboard: true, expected: 'Tool result: deleted /tmp/example' });
    },
  },
  'local-deny': {
    viewport: { width: 390, height: 844 },
    async run(page, step) {
      await open(page, '/conversation', this.viewport);
      await approvalFlow(page, step, { route: 'local', prompt: 'Run the example', action: 'deny', expected: 'Tool denied; no local action ran.' });
    },
  },
  'remote-text': {
    viewport: { width: 1280, height: 900 },
    async run(page, step, events, finish) {
      check(await backendReachable(), 'Backend is down; run `vfc backend start`');
      await open(page, '/remote', this.viewport);
      await send(page, 'Hello', LABELS.en);
      step('send', { prompt: 'Hello' });
      await waitText(page, 'Hello from the pinned AI SDK backend.');
      const final = await waitForSettled(page, LABELS.en);
      step('final', final);
      check(final.composerEditable && final.assistantRows === 1, 'Remote turn did not settle to one answer and an editable composer');
      await finish();
      const posts = chatPosts(events);
      step('network', posts.map(p => ({ status: p.status, uiMessageStream: p.uiMessageStream, bodyCaptured: typeof p.body === 'string', bodyError: p.bodyError })));
      checkChatResponses(posts, 1, 'Hello from the pinned AI SDK backend');
    },
  },
  'remote-approve': remoteApproval('approve', 'The scripted tool call was approved and resumed.', { width: 1280, height: 900 }),
  'remote-deny': remoteApproval('deny', 'The scripted tool call was denied and resumed safely.', { width: 390, height: 844 }),
  'remote-unreachable': {
    viewport: { width: 1280, height: 900 },
    async run(page, step, events, finish) {
      check(!(await backendReachable()), 'Backend is reachable; run `vfc backend stop` first');
      await open(page, '/remote', this.viewport);
      await send(page, 'Hello', LABELS.en);
      step('send', { prompt: 'Hello' });
      await waitText(page, "Can't reach");
      const tree = await aria(page);
      step('error banner', { mentionsStartup: tree.includes('node server.mjs') });
      check(tree.includes('node server.mjs'), 'Error banner lacks the backend startup command');
      check(await page.getByRole('button', { name: 'Dismiss', exact: true }).count() === 1, 'No Dismiss action');
      check(await page.getByRole('button', { name: 'Retry', exact: true }).count() === 0, 'Remote error offers Retry, which the backend cannot honor');
      await snapshot(page, 'remote-unreachable-error');
      await page.getByRole('button', { name: 'Dismiss', exact: true }).click();
      await waitGone(page, "Can't reach");
      const final = await readState(page, LABELS.en);
      step('dismissed', final);
      check(final.composerEditable, 'Composer not editable after dismissing the error');
      await finish();
      check(events.some(e => e.type === 'requestfailed' && e.url.endsWith('/chat')), 'No failed /chat request recorded');
    },
  },
  'rtl-toggle': {
    viewport: { width: 1280, height: 900 },
    async run(page, step) {
      await open(page, '/conversation', this.viewport);
      const ltr = await composerGeometry(page, LABELS.en);
      step('english layout', ltr);
      check(ltr.sendX > ltr.fieldX, 'Send is not to the right of the field in LTR');
      await page.getByRole('button', { name: LABELS.en.toggle, exact: true }).click();
      await page.getByRole('textbox', { name: LABELS.ar.hint, exact: true }).waitFor({ timeout: 10000 });
      const rtl = await composerGeometry(page, LABELS.ar);
      step('arabic layout', rtl);
      check(rtl.sendX < rtl.fieldX, 'Send is not to the left of the field in RTL');
      await approvalFlow(page, step, { route: 'local-ar', prompt: 'Run the example', action: 'approve', expected: 'Tool result: deleted /tmp/example', L: LABELS.ar });
      await snapshot(page, 'rtl-toggle-arabic-final');
      await page.getByRole('button', { name: LABELS.ar.toggle, exact: true }).click();
      await page.getByRole('textbox', { name: LABELS.en.hint, exact: true }).waitFor({ timeout: 10000 });
      const back = await readState(page, LABELS.en);
      step('back to english', back);
      check(back.assistantRows === 1, 'Conversation was lost when switching language');
    },
  },
  'shell-nav': {
    viewport: { width: 1280, height: 900 },
    async run(page, step) {
      await open(page, '/', this.viewport);
      for (const [tab, heading, marker] of [['Completion', 'Completion', 'Quick prompts'], ['Object', 'Object Stream', 'Country'], ['Local', 'Local conversation', 'Local conversation'], ['Remote', 'Remote conversation', 'Remote conversation'], ['Chat', 'Chat', 'Send message']]) {
        await clickTab(page, tab);
        await waitText(page, marker);
        await assertScreen(page, tab, heading);
        step('tab', { tab, heading, marker });
        await snapshot(page, `shell-nav-${tab.toLowerCase()}`);
      }
    },
  },
};

function remoteApproval(action, expected, viewport) {
  return {
    viewport,
    async run(page, step, events, finish) {
      check(await backendReachable(), 'Backend is down; run `vfc backend start`');
      await open(page, '/remote', viewport);
      await approvalFlow(page, step, { route: 'remote', prompt: 'Request approval', action, expected });
      await finish();
      const posts = chatPosts(events);
      step('network', posts.map(p => ({ status: p.status, uiMessageStream: p.uiMessageStream, bodyCaptured: typeof p.body === 'string', bodyError: p.bodyError })));
      checkChatResponses(posts, 2, expected);
      const requests = events.filter(e => e.type === 'request' && e.method === 'POST' && e.url.endsWith('/chat'));
      check(requests.length === 2 && (requests[1].postData || '').includes(`"approved":${action === 'approve'}`), `Continuation request does not carry approved:${action === 'approve'}`);
    },
  };
}

async function composerGeometry(page, L) {
  const field = await page.getByRole('textbox', { name: L.hint, exact: true }).boundingBox();
  const sendButton = await page.getByRole('button', { name: L.send, exact: true }).boundingBox();
  return { fieldX: Math.round(field.x), sendX: Math.round(sendButton.x) };
}

async function clickTab(page, label) {
  const tab = page.getByRole('tab', { name: label });
  if (await tab.count()) return tab.first().click();
  return page.getByRole('button', { name: label }).first().click();
}

async function assertScreen(page, tab, heading) {
  const selectedTab = page.getByRole('tab', { name: tab, exact: true });
  check(await selectedTab.count() === 1, `Expected one ${tab} tab`);
  check(await selectedTab.getAttribute('aria-selected') === 'true', `${tab} tab is not selected`);
  check(await page.getByRole('heading', { name: heading, exact: true }).count() === 1, `Expected the ${heading} screen heading`);
}

async function runScenario(name, session) {
  const scenario = SCENARIOS[name];
  if (!scenario) throw new Error(`Unknown scenario ${name}. Known: ${Object.keys(SCENARIOS).join(', ')}`);
  const steps = [];
  const step = (action, observed) => steps.push({ action, ...(observed === undefined ? {} : { observed }) });
  let failure;
  const finish = () => session.finish();
  try {
    await scenario.run.call(scenario, session.page, step, session.events, finish);
  } catch (error) {
    failure = String(error.message || error);
  }
  let artifacts = [];
  try {
    artifacts = await snapshot(session.page, `${name}-final`);
  } catch (error) {
    const snapshotFailure = `Final snapshot failed: ${String(error.message || error)}`;
    failure = failure ? `${failure}; ${snapshotFailure}` : snapshotFailure;
  }
  await finish();
  const errors = session.events.filter(e => e.type === 'pageerror' || (e.type === 'console-error' && name !== 'remote-unreachable'));
  if (!failure && errors.length) failure = `Page errors: ${errors.map(e => e.text).join(' | ')}`;
  const state = fs.readFileSync(path.join(RUN_DIR, 'state.env'), 'utf8');
  const result = {
    scenario: name, passed: !failure, failure, capturedAt: new Date().toISOString(),
    build: Object.fromEntries(state.trim().split('\n').map(l => l.split('=')).filter(([k]) => /^(BUILD_|KEY_BAKED|BACKEND_URL)/.test(k))),
    viewport: scenario.viewport, steps, artifacts,
    network: session.events.filter(e => e.type !== 'console-error' && e.type !== 'pageerror'),
    errors: session.events.filter(e => e.type === 'console-error' || e.type === 'pageerror'),
  };
  const file = path.join(EVIDENCE, `${name}.json`);
  fs.writeFileSync(file, JSON.stringify(result, null, 2) + '\n');
  console.log(`${result.passed ? 'PASS' : 'FAIL'} ${name}${failure ? `: ${failure}` : ''}`);
  console.log(`evidence: ${file}`);
  return result.passed;
}

const HELP = `Usage: vfc browser <command> [args]

  open [route] [--width W --height H]   Fresh app instance at #<route> (/, /conversation, /remote). Prints the a11y tree.
  aria                                  Print the current accessibility tree.
  tab <label>                           Click a bottom-navigation tab (Chat, Completion, Object, Local, Remote).
  click --name N [--role button] [--keyboard] [--substring]
                                        Click (or focus + Enter) the element with that accessible name.
  type --name N --text T [--role textbox]
                                        Type into a field key by key and verify its value.
  send <text> [--expect T] [--lang en|ar]
                                        Type into the composer, press Send, optionally wait for text T.
  wait-text <text> [--timeout ms]       Wait until text appears in the accessibility tree.
  state [--lang en|ar]                  Print composer/approval/message-count state as JSON.
  snapshot --name X                     Save X.aria.txt and X.png in the evidence dir.

Usage: vfc scenario <name>
  ${Object.keys(SCENARIOS).join(', ')}`;

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  if (!command || command === 'help' || command === '--help') { console.log(HELP); return; }
  const { positional, flags } = parseArgs(rest);
  const required = {
    tab: [positional[0], 'tab label'],
    click: [flags.name, '--name'],
    type: [flags.name, '--name'],
    send: [positional[0], 'message text'],
    'wait-text': [positional[0], 'text'],
    scenario: [positional[0], 'scenario name'],
  }[command];
  if (required && !required[0]) throw new Error(`Missing ${required[1]}`);
  if (command === 'type' && typeof flags.text !== 'string') throw new Error('Missing --text value');
  if (command === 'click' && typeof flags.name !== 'string') throw new Error('Missing --name value');
  if (command === 'type' && typeof flags.name !== 'string') throw new Error('Missing --name value');
  if (command === 'snapshot' && flags.name !== undefined && typeof flags.name !== 'string') throw new Error('Missing --name value');
  if (flags.lang && !LABELS[flags.lang]) throw new Error(`Unknown language: ${flags.lang}`);
  const session = await connect([command, ...rest].join(' '));
  const { page } = session;
  const L = LABELS[flags.lang || 'en'];
  try {
    switch (command) {
      case 'open':
        await open(page, positional[0] || '/', { width: flags.width || 1280, height: flags.height || 900 });
        console.log(await aria(page));
        break;
      case 'aria':
        await ensureSemantics(page);
        console.log(await aria(page));
        break;
      case 'tab':
        await ensureSemantics(page);
        await clickTab(page, positional[0]);
        break;
      case 'click': {
        await ensureSemantics(page);
        const target = page.getByRole(flags.role || 'button', { name: flags.name, exact: !flags.substring });
        if (flags.keyboard) { await target.focus(); await page.keyboard.press('Enter'); } else await target.click();
        break;
      }
      case 'type':
        await ensureSemantics(page);
        await typeInto(page, page.getByRole(flags.role || 'textbox', { name: flags.name, exact: true }), flags.text);
        break;
      case 'send':
        await ensureSemantics(page);
        await send(page, positional[0], L);
        if (flags.expect) await waitText(page, flags.expect, flags.timeout || 30000);
        else await page.waitForTimeout(1000);
        console.log(JSON.stringify(await readState(page, L)));
        break;
      case 'wait-text':
        await ensureSemantics(page);
        await waitText(page, positional[0], flags.timeout || 30000);
        break;
      case 'state':
        await ensureSemantics(page);
        console.log(JSON.stringify(await readState(page, L), null, 2));
        break;
      case 'snapshot':
        await ensureSemantics(page);
        console.log((await snapshot(page, flags.name || `snapshot-${Date.now()}`)).join('\n'));
        break;
      case 'scenario':
        process.exitCode = (await runScenario(positional[0], session)) ? 0 : 1;
        return;
      default:
        console.error(HELP);
        process.exitCode = 2;
    }
  } finally {
    await session.finish();
  }
}

main().then(() => process.exit(process.exitCode || 0), error => { console.error(String(error.message || error)); process.exit(1); });
