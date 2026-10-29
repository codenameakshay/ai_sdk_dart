#!/usr/bin/env node
// Drives the flutter_chat or advanced_app web build (VFC_APP, set by vfc from
// the run state) in the run's headless Chromium over CDP.
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
const APP = process.env.VFC_APP || 'flutter_chat';

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

// flutter_chat routes are hash routes (#/remote). advanced_app picks its page
// from the query string (?page=widget-gallery[&state=approval]); the route
// argument is `<page>` or `<page>?state=<fixture>`, e.g. `tools-chat?state=error`.
function appUrl(route) {
  if (APP === 'advanced_app') {
    const [pageName, extra] = String(route === '/' ? 'provider-chat' : route).replace(/^\//, '').split('?');
    if (!/^[a-z-]+$/.test(pageName)) throw new Error(`Invalid advanced_app page: ${route}`);
    if (extra !== undefined && !/^[A-Za-z0-9_=&-]+$/.test(extra)) throw new Error(`Invalid query: ${extra}`);
    return `${WEB}/?page=${pageName}${extra ? `&${extra}` : ''}`;
  }
  return `${WEB}/#${route.startsWith('/') ? route : `/${route}`}`;
}

async function open(page, route = '/', { width = 1280, height = 900 } = {}) {
  await page.setViewportSize({ width: Number(width), height: Number(height) });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  // about:blank first so a hash-only change still boots a fresh app instance.
  await page.goto('about:blank');
  await page.goto(appUrl(route));
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

// Flutter only builds semantics for rows near the viewport, so a long page is
// scrolled with the mouse wheel until the target appears in the viewport.
// `at` is the pointer position: the default targets the page, a locator targets a nested list.
const viewport = page => page.evaluate(() => ({ width: window.innerWidth, height: window.innerHeight }));

async function wheel(page, dy, at) {
  const size = await viewport(page);
  let x = size.width / 2, y = size.height / 2;
  if (at) {
    const box = await at.boundingBox();
    if (!box) throw new Error('Scroll target has no box');
    x = box.x + box.width / 2; y = box.y + box.height / 2;
  }
  await page.mouse.move(x, y);
  await page.mouse.wheel(0, dy);
  await page.waitForTimeout(250);
}

async function inViewport(page, locator) {
  if (await locator.count() === 0) return false;
  const box = await locator.first().boundingBox();
  const size = await viewport(page);
  return !!box && box.y >= 0 && box.y + Math.min(box.height, 40) <= size.height && box.x >= 0 && box.x < size.width;
}

async function scrollTo(page, locator, { at, maxSteps = 60 } = {}) {
  const size = await viewport(page);
  // Down first, then up if the target was above the start position.
  for (const dir of [1, -1]) {
    for (let i = 0; i < maxSteps; i++) {
      if (await inViewport(page, locator)) {
        // Park the target in the upper third so the content below it is also built and visible.
        const box = await locator.first().boundingBox();
        const want = size.height * 0.15;
        if (Math.abs(box.y - want) > 40 && !at) await wheel(page, box.y - want, at);
        return;
      }
      await wheel(page, dir * size.height * 0.5, at);
    }
  }
  throw new Error('Could not scroll the target into view');
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

// ── advanced_app scenarios (keyless): select with VFC_APP=advanced_app at build time. ──

const ADV_VIEWPORT = { width: 1280, height: 900 };

const escapeRegExp = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// SnackBars are short-lived and their text also appears elsewhere in the tree
// ("Regenerate" vs the "Regenerate response" button), so match a text node that
// starts with it. A hovered tooltip can be merged into the same node.
async function waitSnack(page, text, timeout = 5000) {
  const pattern = new RegExp(`^\\s*- text: "?${escapeRegExp(text)}(?:["\\s].*)?$`, 'm');
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (pattern.test(await aria(page))) return;
    await page.waitForTimeout(50);
  }
  throw new Error(`Snack bar never showed: ${text}`);
}

async function clickSnack(page, step, locator, expected) {
  await locator.click();
  await waitSnack(page, expected);
  step('click', { expected });
}

const advButton = (page, name, exact = true) => page.getByRole('button', { name, exact });
const advGroup = (page, name) => page.getByRole('group', { name, exact: false });

async function advHeading(page, title) {
  check(await page.getByRole('heading', { name: title, exact: true }).count() >= 1, `Expected the ${title} app bar title`);
}

async function openDrawerPage(page, label) {
  await advButton(page, 'Open navigation menu').click();
  const item = advButton(page, label);
  await item.waitFor({ timeout: 10000 });
  await item.click();
  await page.getByRole('heading', { name: label, exact: true }).first().waitFor({ timeout: 10000 });
}

// Luminance (0..1) of one screenshot pixel, decoded in the page so no image library is needed.
async function pixelLuminance(page, x, y) {
  const png = (await page.screenshot()).toString('base64');
  return page.evaluate(async ({ png, x, y }) => {
    const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${png}`)).blob());
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    context.drawImage(bitmap, 0, 0);
    const [r, g, b] = context.getImageData(x, y, 1, 1).data;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  }, { png, x, y });
}

function requireKeylessBuild() {
  const keys = [...fs.readFileSync(path.join(RUN_DIR, 'state.env'), 'utf8').matchAll(/^KEYS_BAKED=(.*)$/gm)].at(-1)?.[1] || '';
  check(keys === '', `This build has provider keys baked in (${keys}); the keyless guards only exist without them. Build again without the keys.`);
}

const GALLERY_SECTIONS = [
  // [slug, locator of the section card]
  ['prompt-suggestions', page => advGroup(page, 'PromptSuggestions')],
  ['typing-indicator', page => advGroup(page, 'TypingIndicator')],
  ['assistant-message-view', page => advGroup(page, 'AssistantMessageView')],
  ['tool-approval-card', page => advGroup(page, 'ToolApprovalCard')],
  ['tool-call-card', page => advGroup(page, 'ToolCallCard')],
  ['message-actions-bar', page => advGroup(page, 'MessageActionsBar')],
  ['media', page => page.getByRole('img', { name: 'Media — MessageImage', exact: false }).first()],
  ['usage-view', page => page.getByText('UsageView Token usage')],
  ['chat-error-view', page => advGroup(page, 'ChatErrorView')],
  ['object-stream-view', page => advGroup(page, 'ObjectStreamView')],
  ['scroll-to-bottom-button', page => advGroup(page, 'ScrollToBottomButton')],
];

async function gallerySection(page, step, slug) {
  const [, locate] = GALLERY_SECTIONS.find(([name]) => name === slug);
  await scrollTo(page, locate(page));
  step('section', { slug });
}

async function gallerySnapshot(page, slug) {
  await snapshot(page, `widget-gallery-${slug}`);
}

Object.assign(SCENARIOS, {
  'widget-gallery': {
    app: 'advanced_app',
    viewport: ADV_VIEWPORT,
    async run(page, step) {
      // Let the page read back the clipboard that Copy writes (browser permission, not an app change).
      const browserSession = await page.context().browser().newBrowserCDPSession();
      await browserSession.send('Browser.grantPermissions', { origin: WEB_ORIGIN, permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'] });
      await open(page, 'widget-gallery', this.viewport);
      await advHeading(page, 'Widget Gallery');
      await waitText(page, 'no API key required');

      // PromptSuggestions
      await gallerySection(page, step, 'prompt-suggestions');
      for (const chip of ['Summarise my notes', 'Plan a trip to Kyoto', 'Explain async/await']) {
        check(await page.getByRole('checkbox', { name: chip, exact: true }).count() === 1, `Missing suggestion chip: ${chip}`);
      }
      await clickSnack(page, step, page.getByRole('checkbox', { name: 'Plan a trip to Kyoto', exact: true }), 'Selected: Plan a trip to Kyoto');
      await gallerySnapshot(page, 'prompt-suggestions');

      // TypingIndicator
      await gallerySection(page, step, 'typing-indicator');
      await waitText(page, 'TypingIndicator Shown while waiting for the first token.');
      check((await aria(page)).includes('Assistant is typing'), 'Typing indicator label missing');
      await gallerySnapshot(page, 'typing-indicator');

      // AssistantMessageView: reasoning, text, tool call + result, source from one message
      await gallerySection(page, step, 'assistant-message-view');
      let tree = await aria(page);
      for (const expected of ['It is currently 22°C and sunny in Tokyo.', 'Tool call: getWeather', 'Tool result', 'Open source: Tokyo Weather — example.com']) {
        check(tree.includes(expected), `AssistantMessageView lacks: ${expected}`);
      }
      check(!tree.includes('The user asked about the weather in Tokyo'), 'Reasoning is expanded before the user asked');
      await advButton(page, 'Reasoning').click();
      await waitText(page, 'The user asked about the weather in Tokyo', 5000);
      step('reasoning expanded');
      await clickSnack(page, step, page.getByText('Open source: Tokyo Weather — example.com'), 'Open: https://weather.example.com/tokyo');
      await gallerySnapshot(page, 'assistant-message-view');

      // ToolApprovalCard: approve and deny, each with a reason
      await gallerySection(page, step, 'tool-approval-card');
      check((await aria(page)).includes('Tool approval required for deleteFile'), 'Approval card is missing');
      await typeInto(page, page.getByRole('textbox', { name: 'Reason (optional)', exact: true }), 'looks safe');
      await clickSnack(page, step, advButton(page, 'Approve'), 'Approved — looks safe');
      await gallerySnapshot(page, 'tool-approval-card');
      await typeInto(page, page.getByRole('textbox', { name: 'Reason (optional)', exact: true }), 'too risky');
      await clickSnack(page, step, advButton(page, 'Deny'), 'Denied — too risky');

      // ToolCallCard: a result and an error
      await gallerySection(page, step, 'tool-call-card');
      tree = await aria(page);
      for (const expected of ['Tool call: calculate', 'Result 63', 'Tool call: fetchUrl', 'Tool error', 'SocketException: failed host lookup']) {
        check(tree.includes(expected), `ToolCallCard lacks: ${expected}`);
      }
      await gallerySnapshot(page, 'tool-call-card');

      // MessageActionsBar
      await gallerySection(page, step, 'message-actions-bar');
      await clickSnack(page, step, advButton(page, 'Copy message'), 'Copied to clipboard');
      const clipboard = await page.evaluate(() => navigator.clipboard.readText().catch(error => `unreadable: ${error.message}`));
      step('clipboard', { clipboard });
      check(clipboard === 'It is currently 22°C and sunny in Tokyo.', `Clipboard holds "${clipboard}" after Copy`);
      await clickSnack(page, step, advButton(page, 'Regenerate response'), 'Regenerate');
      await clickSnack(page, step, advButton(page, 'Good response'), '👍 Thanks for the feedback');
      await clickSnack(page, step, advButton(page, 'Bad response'), '👎 Thanks for the feedback');
      await gallerySnapshot(page, 'message-actions-bar');

      // MessageImage (a remote URL is blocked by default) and MessageAttachment
      await gallerySection(page, step, 'media');
      tree = await aria(page);
      check(tree.includes('Remote image blocked'), 'MessageImage did not block the remote image by default');
      check(tree.includes('Attachment: design-spec.pdf application/pdf'), 'MessageAttachment is missing');
      await clickSnack(page, step, advButton(page, 'Attachment: design-spec.pdf application/pdf'), 'Open attachment');
      await gallerySnapshot(page, 'media');

      // UsageView
      await gallerySection(page, step, 'usage-view');
      await waitText(page, 'Input 1240 Output 318');
      step('usage', { input: 1240, output: 318 });
      await gallerySnapshot(page, 'usage-view');

      // ChatErrorView
      await gallerySection(page, step, 'chat-error-view');
      await waitText(page, 'Connection timed out after 30s');
      await clickSnack(page, step, advButton(page, 'Retry'), 'Retry');
      await clickSnack(page, step, advButton(page, 'Dismiss'), 'Dismissed');
      await gallerySnapshot(page, 'chat-error-view');

      // ObjectStreamView: fields arrive one by one from the synthetic stream
      await gallerySection(page, step, 'object-stream-view');
      await waitText(page, 'Press Stream to watch fields arrive live.');
      await gallerySnapshot(page, 'object-stream-view-empty');
      await advButton(page, 'Stream a sample object').click();
      let partial;
      const deadline = Date.now() + 10000;
      while (Date.now() < deadline) {
        const now = await aria(page);
        if (now.includes('\\"country\\": \\"Japan\\"') && !now.includes('currency')) { partial = now; break; }
        if (now.includes('currency')) break;
        await page.waitForTimeout(40);
      }
      check(partial, 'Never observed a partial object (country without currency)');
      step('partial object observed', { hasCountry: true, hasCurrency: false });
      await snapshot(page, 'widget-gallery-object-stream-view-partial');
      await waitText(page, '\\"currency\\": \\"Japanese yen (JPY)\\"', 10000);
      tree = await aria(page);
      for (const expected of ['\\"capital\\": \\"Tokyo\\"', '\\"population\\": \\"125 million\\"']) check(tree.includes(expected), `Final object lacks ${expected}`);
      step('final object observed');
      await gallerySnapshot(page, 'object-stream-view');

      // ScrollToBottomButton on the mini list: visible at the top, gone at the bottom, back after scrolling up
      await gallerySection(page, step, 'scroll-to-bottom-button');
      const latest = advButton(page, 'Scroll to latest message');
      check(await latest.count() === 1, 'Scroll-to-latest button is hidden while the list is at the top');
      await gallerySnapshot(page, 'scroll-to-bottom-button-top');
      await latest.click();
      await waitText(page, 'Message 30', 5000);
      await waitGone(page, 'Scroll to latest message', 5000);
      step('jumped to latest; button hidden');
      await gallerySnapshot(page, 'scroll-to-bottom-button-bottom');
      await wheel(page, -700, page.getByText('Message 30').first());
      await waitText(page, 'Scroll to latest message', 5000);
      step('scrolled up; button visible again');
      await gallerySnapshot(page, 'scroll-to-bottom-button');
    },
  },

  'widget-gallery-dark': {
    app: 'advanced_app',
    viewport: ADV_VIEWPORT,
    async run(page, step) {
      try {
        await page.emulateMedia({ colorScheme: 'light' });
        await open(page, 'widget-gallery', this.viewport);
        const light = await pixelLuminance(page, 640, 800);
        await page.emulateMedia({ colorScheme: 'dark' });
        await open(page, 'widget-gallery', this.viewport);
        await waitText(page, 'no API key required');
        const dark = await pixelLuminance(page, 640, 800);
        step('background luminance', { light: Number(light.toFixed(3)), dark: Number(dark.toFixed(3)) });
        check(light > 0.8, `Light theme background is not light (luminance ${light})`);
        check(dark < 0.2, `Dark theme background is not dark (luminance ${dark})`);
        await snapshot(page, 'widget-gallery-dark-top');
        await scrollTo(page, advGroup(page, 'ToolApprovalCard'));
        await snapshot(page, 'widget-gallery-dark-approval');
        await scrollTo(page, advGroup(page, 'ChatErrorView'));
        await snapshot(page, 'widget-gallery-dark-error');
      } finally {
        await page.emulateMedia({ colorScheme: null });
      }
    },
  },

  'tools-chat-fixtures': {
    app: 'advanced_app',
    viewport: ADV_VIEWPORT,
    async run(page, step) {
      const composer = name => page.getByRole('textbox', { name, exact: true });

      await open(page, 'tools-chat?state=normal', this.viewport);
      await waitText(page, 'Offline fixture reply');
      let tree = await aria(page);
      check(tree.includes('User message What can this page do?'), 'Fixture user bubble missing');
      check(tree.includes('Assistant message'), 'Fixture assistant bubble missing');
      await typeInto(page, composer('Ask about weather or math…'), 'hello');
      await advButton(page, 'Send message').click();
      const cleared = Date.now() + 3000;
      while (Date.now() < cleared && await composer('Ask about weather or math…').inputValue() !== '') await page.waitForTimeout(100);
      check(await composer('Ask about weather or math…').inputValue() === '', 'ChatComposer did not clear after Send');
      step('normal: composer clears on Send; fixture onSend is a no-op');
      await snapshot(page, 'tools-chat-normal');

      await open(page, 'tools-chat?state=approval', this.viewport);
      await waitText(page, 'Tool approval required for deleteFile');
      const pendingComposer = composer('Approval pending…');
      check(!(await pendingComposer.isEditable()), 'Composer is editable while approval is pending');
      check(!(await advButton(page, 'Send message').isEnabled()), 'Send is enabled while approval is pending');
      step('approval: composer locked');
      await snapshot(page, 'tools-chat-approval-pending');
      await clickSnack(page, step, advButton(page, 'Approve'), 'Approved fixture action');
      await snapshot(page, 'tools-chat-approval-approved');
      await open(page, 'tools-chat?state=approval', this.viewport);
      await clickSnack(page, step, advButton(page, 'Deny'), 'Denied fixture action');

      await open(page, 'tools-chat?state=error', this.viewport);
      await waitText(page, 'Bad state: Fixture request failed');
      await snapshot(page, 'tools-chat-error');
      await clickSnack(page, step, advButton(page, 'Retry'), 'Retry');
      await clickSnack(page, step, advButton(page, 'Dismiss'), 'Dismissed fixture error');

      await open(page, 'tools-chat?state=sources-tool', this.viewport);
      await waitText(page, 'Source: Example Weather Feed');
      tree = await aria(page);
      for (const expected of ['User message What is the weather in Tokyo?', 'Tool call: getWeather', 'Sunny, 22°C in Tokyo.', 'It is currently 22°C and sunny in Tokyo.', 'Sources']) {
        check(tree.includes(expected), `sources-tool fixture lacks: ${expected}`);
      }
      // This fixture renders ReasoningView expanded (initiallyExpanded: true).
      check(tree.includes('Use the weather tool and cite the source.'), 'Fixture reasoning is not expanded');
      step('sources-tool: reasoning, tool card, answer and source shown');
      await snapshot(page, 'tools-chat-sources-tool');

      await open(page, 'tools-chat?state=long-history', this.viewport);
      await waitText(page, 'Conversation history 1');
      await scrollTo(page, page.getByText('Conversation history 12'));
      step('long-history: first and last rows reachable');
      await snapshot(page, 'tools-chat-long-history');
    },
  },

  'conversation-ui': {
    app: 'advanced_app',
    viewport: ADV_VIEWPORT,
    async run(page, step) {
      // The page passes hintText itself, which wins over AiSdkUiStrings, so the field keeps its English hint in RTL.
      const hint = 'Ask about weather, or request a file deletion…';
      await open(page, 'conversation', this.viewport);
      await waitText(page, 'Ask about the weather or say "delete q3.pdf"');
      check(!(await advButton(page, 'Restore snapshot').isEnabled()), 'Restore is enabled before anything was saved');
      await clickSnack(page, step, advButton(page, 'Retry last turn'), 'There is no failed assistant turn to retry.');
      await clickSnack(page, step, advButton(page, 'Save snapshot'), 'Saved (0 messages).');
      check(await advButton(page, 'Restore snapshot').isEnabled(), 'Restore stayed disabled after Save');
      await clickSnack(page, step, advButton(page, 'Restore snapshot'), 'Conversation restored.');
      await advButton(page, 'New conversation').click();
      await waitText(page, 'Ask about the weather or say "delete q3.pdf"');
      step('new conversation: empty state again');

      await waitGone(page, 'Conversation restored.', 10000); // keep the snack bar out of the screenshots
      const ltr = await geometry(page, hint, 'Send message');
      step('english layout', ltr);
      check(ltr.sendX > ltr.fieldX, 'Send is not to the right of the field in LTR');
      await snapshot(page, 'conversation-ui-english');
      await advButton(page, 'Switch to RTL (Arabic)').click();
      await advButton(page, 'إرسال').waitFor({ timeout: 10000 });
      const rtl = await geometry(page, hint, 'إرسال');
      step('arabic layout', rtl);
      check(rtl.sendX < rtl.fieldX, 'Send is not to the left of the field in RTL');
      check(await advButton(page, 'Switch to LTR', false).count() === 1, 'RTL toggle tooltip did not change');
      await snapshot(page, 'conversation-ui-arabic');
      await advButton(page, 'Switch to LTR', false).click();
      await advButton(page, 'Send message').waitFor({ timeout: 10000 });
      step('back to english');
    },
  },

  'keyless-guards': {
    app: 'advanced_app',
    viewport: ADV_VIEWPORT,
    async run(page, step, events) {
      requireKeylessBuild();
      // An empty field's name also carries its placeholder, so match the label as a substring.
      const textbox = name => page.getByRole('textbox', { name, exact: false });

      await open(page, 'image-gen', this.viewport);
      await typeInto(page, textbox('Prompt'), 'A lighthouse at dawn');
      await advButton(page, 'Generate').click();
      await waitText(page, 'Set OPENAI_API_KEY to use image generation.');
      step('image-gen guard');
      await snapshot(page, 'keyless-image-gen');

      await open(page, 'embeddings', this.viewport);
      await typeInto(page, textbox('Text 1'), 'cat');
      await typeInto(page, textbox('Text 2'), 'kitten');
      await advButton(page, 'Compare').click();
      await waitText(page, 'Set OPENAI_API_KEY for OpenAI embeddings.');
      await advButton(page, 'Google').click();
      await advButton(page, 'Compare').click();
      await waitText(page, 'Set GOOGLE_API_KEY for Google embeddings.');
      step('embeddings compare guards (OpenAI, Google)');
      await snapshot(page, 'keyless-embeddings');

      await open(page, 'tts', this.viewport);
      await advButton(page, 'Speak').click();
      await waitText(page, 'Set OPENAI_API_KEY to use TTS.');
      step('tts guard');

      await open(page, 'stt', this.viewport);
      await advButton(page, 'Start Recording').click();
      await waitText(page, 'Set OPENAI_API_KEY to use STT.');
      step('stt guard');

      await open(page, 'multimodal', this.viewport);
      check(!(await advButton(page, 'Analyze').isEnabled()), 'Analyze is enabled without an image');
      step('multimodal: Analyze disabled without an image');

      await open(page, 'responses', this.viewport);
      await typeInto(page, textbox('Prompt'), 'hello');
      await advButton(page, 'Ask').click();
      await waitText(page, 'Set the API key for the selected provider.');
      step('responses guard');
      await snapshot(page, 'keyless-responses');

      const providerCalls = events.filter(e => e.type === 'request' && /(openai\.com|anthropic\.com|googleapis\.com)/.test(new URL(e.url).hostname));
      step('provider requests', { count: providerCalls.length });
      check(providerCalls.length === 0, `Keyless guards still sent ${providerCalls.length} request(s) to a provider`);
    },
  },

  'drawer-nav': {
    app: 'advanced_app',
    viewport: ADV_VIEWPORT,
    async run(page, step) {
      await open(page, '/', this.viewport);
      await advHeading(page, 'Provider Chat');
      step('default page', { title: 'Provider Chat' });
      for (const label of ['Tools Chat', 'Image Gen', 'Multimodal', 'Embeddings', 'Text-to-Speech', 'Speech-to-Text', 'Completion', 'Object Stream', 'Conversation', 'Responses', 'Widget Gallery']) {
        await openDrawerPage(page, label);
        step('page', { label });
        await snapshot(page, `drawer-nav-${label.toLowerCase().replace(/[^a-z]+/g, '-')}`);
      }
    },
  },
});

async function geometry(page, fieldName, sendName) {
  const field = await page.getByRole('textbox', { name: fieldName, exact: true }).boundingBox();
  const sendButton = await page.getByRole('button', { name: sendName, exact: true }).boundingBox();
  return { fieldX: Math.round(field.x), sendX: Math.round(sendButton.x) };
}

const scenarioNames = () => Object.entries(SCENARIOS).filter(([, s]) => (s.app || 'flutter_chat') === APP).map(([n]) => n);

async function runScenario(name, session) {
  const scenario = SCENARIOS[name];
  if (!scenario) throw new Error(`Unknown scenario ${name}. Known for ${APP}: ${scenarioNames().join(', ')}`);
  if ((scenario.app || 'flutter_chat') !== APP) throw new Error(`Scenario ${name} is for ${scenario.app || 'flutter_chat'}; this run was built for ${APP}. Known for ${APP}: ${scenarioNames().join(', ')}`);
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
    build: Object.fromEntries(state.trim().split('\n').map(l => l.split('=')).filter(([k]) => /^(BUILD_|APP$|KEYS?_BAKED$|BACKEND_URL$)/.test(k))),
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

  open [route] [--width W --height H]   Fresh app instance. flutter_chat routes: /, /conversation, /remote.
                                        advanced_app pages: provider-chat, tools-chat[?state=normal|approval|error|sources-tool|long-history],
                                        image-gen, multimodal, embeddings, tts, stt, completion, object-stream, conversation,
                                        responses, widget-gallery. Prints the a11y tree.
  aria                                  Print the current accessibility tree.
  tab <label>                           flutter_chat: click a bottom-navigation tab (Chat, Completion, Object, Local, Remote).
  nav <label>                           advanced_app: open the drawer and pick a page (Widget Gallery, Tools Chat, ...).
  click --name N [--role button] [--keyboard] [--substring]
                                        Click (or focus + Enter) the element with that accessible name.
  type --name N --text T [--role textbox] [--substring]
                                        Type into a field key by key and verify its value.
  send <text> [--expect T] [--lang en|ar] [--hint H]
                                        Type into the composer, press Send, optionally wait for text T.
  wait-text <text> [--timeout ms]       Wait until text appears in the accessibility tree.
  scroll (--to N [--role group] [--substring] | --by PX)
                                        Mouse-wheel the page until the element is in view (long pages build rows lazily).
  state [--lang en|ar] [--hint H]       Print composer/approval/message-count state as JSON.
  snapshot --name X                     Save X.aria.txt and X.png in the evidence dir.

Usage: vfc scenario <name>   (scenarios for this run's app: ${scenarioNames().join(', ')})`;

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  if (!command || command === 'help' || command === '--help') { console.log(HELP); return; }
  const { positional, flags } = parseArgs(rest);
  const required = {
    tab: [positional[0], 'tab label'],
    nav: [positional[0], 'page label'],
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
  if (flags.hint !== undefined && typeof flags.hint !== 'string') throw new Error('Missing --hint value');
  if (flags.lang && !LABELS[flags.lang]) throw new Error(`Unknown language: ${flags.lang}`);
  const session = await connect([command, ...rest].join(' '));
  const { page } = session;
  const L = { ...LABELS[flags.lang || 'en'], ...(flags.hint === undefined ? {} : { hint: flags.hint }) };
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
        if (APP !== 'flutter_chat') throw new Error('`tab` is for flutter_chat; advanced_app uses `nav <label>`');
        await ensureSemantics(page);
        await clickTab(page, positional[0]);
        break;
      case 'nav':
        if (APP !== 'advanced_app') throw new Error('`nav` is for advanced_app; flutter_chat uses `tab <label>`');
        await ensureSemantics(page);
        await openDrawerPage(page, positional[0]);
        break;
      case 'click': {
        await ensureSemantics(page);
        const target = page.getByRole(flags.role || 'button', { name: flags.name, exact: !flags.substring });
        if (flags.keyboard) { await target.focus(); await page.keyboard.press('Enter'); } else await target.click();
        break;
      }
      case 'scroll': {
        await ensureSemantics(page);
        if (flags.to) await scrollTo(page, page.getByRole(flags.role || 'group', { name: flags.to, exact: !flags.substring }));
        else await wheel(page, Number(flags.by || 400));
        break;
      }
      case 'type':
        await ensureSemantics(page);
        await typeInto(page, page.getByRole(flags.role || 'textbox', { name: flags.name, exact: !flags.substring }), flags.text);
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
