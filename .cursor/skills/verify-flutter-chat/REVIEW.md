# Flutter verification harness review

Scope: `scripts/vfc`, `scripts/drive.cjs`, and this skill's feature documentation. No package/example edits, dependency installs, real provider requests, commits, or toolchain changes were used during this independent review pass. An earlier worker ran one real build (including its pub-get step); that was not repeated here. Lifecycle probes use synthetic Flutter output and owned Chromium processes. The parent independently reran every confirmed finding.

## Confirmed findings and fixes

1. Evidence could be placed under another run's scratch directory. The old check compared only the current run's two directories; cleaning the other run could delete this run's evidence. Run/evidence roots now must be disjoint, including resolved symlink ancestry.
2. Startup TERM/INT handlers cleaned up but resumed execution, allowing `up` to report ready after cancellation. Handlers now exit with 143/130, deferring exit only while a launched child gets its identity recorded. Both before-launch and child-before-recording signal checkpoints were reproduced.
3. Shutdown verified identity before TERM but not before delayed KILL. A replaced PID/group could receive KILL. Identity is now rechecked before escalation; failure retains scratch for inspection.
4. Advanced Tools Chat and Conversation have custom composer hints, but documented `send`/`state` commands assumed `Message…`. Both commands now accept `--hint`; live-page documentation supplies the actual hints.
5. The keyless guard read the first `KEYS_BAKED` entry, while rebuilds append metadata and lifecycle commands use the last entry. Keyless→keyed rebuilds wrongly passed, and keyed→keyless rebuilds wrongly failed. The guard now reads the last entry. Scenario evidence also records `APP` and `KEYS_BAKED`.

The earlier worker's codex-only ID restriction was reverted: generated IDs still start with `codex-`, but existing safe IDs remain accepted. Fixture documentation now explicitly states that the normal fixture's Send callback is a no-op; approval snack bars do not prove model execution or approval continuation.

## Lifecycle reproduction

Run from the repository root. These commands can target either reviewed script version using `S`; the before/after results below were captured against the original working-tree snapshot and the fixed script. Temporary executable probes/snapshots were removed after independent verification.

Common setup, in a fresh shell for each probe:

```bash
S=.cursor/skills/verify-flutter-chat/scripts/vfc
repo=$PWD
probe=$(mktemp -d /tmp/codex-vfc-review.XXXXXX)
export VERIFY_RUN_ID=codex-review-$$
export VFC_RUNS_ROOT=$probe/runs VFC_EVIDENCE_ROOT=$probe/evidence
unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY
source <(sed '/^case "${1:-}" in/,$d' "$S")
REPO=$repo
SKILL_DIR=$repo/.cursor/skills/verify-flutter-chat
trap 'VERIFY_RUN_ID="$VERIFY_RUN_ID" cmd_down' EXIT
synthetic_flutter() {
  [[ "$1" != pub ]] || return 0
  local out='' arg
  while (($#)); do arg=$1; shift; if [[ $arg == -o ]]; then out=$1; shift; fi; done
  mkdir -p "$out"; printf 'synthetic artifact\n' >"$out/main.dart.js"
}
```

Root overlap (before accepts; after rejects):

```bash
EVIDENCE_ROOT=$RUNS_ROOT/codex-other-owned-run
(require_run) && echo ACCEPTED || echo REJECTED
EVIDENCE_ROOT=$probe/evidence
```

Cancellation before the first child (before prints ready; after exits 143 and cleans):

```bash
FLUTTER=synthetic_flutter VFC_APP=advanced_app cmd_build
CHROMIUM=$(command -v chromium || command -v google-chrome)
eval "$(declare -f start_group | sed '1s/start_group/original_start_group/')"
start_group() { if [[ $1 == web ]]; then kill -TERM "$BASHPID"; fi; original_start_group "$@"; }
(cmd_up)
```

For cancellation after launch but before PID recording, replace the wrapper and final call above with:

```bash
eval "$(declare -f proc_identity | sed '1s/proc_identity/original_proc_identity/')"
start_group() { STARTING_GROUP=yes; original_start_group "$@"; STARTING_GROUP=no; }
proc_identity() {
  if [[ ${STARTING_GROUP:-no} == yes && ! -f $probe/signalled ]]; then
    touch "$probe/signalled"; kill -TERM "$startup_pid"
  fi
  original_proc_identity "$@"
}
(startup_pid=$BASHPID; cmd_up)
```

Identity change during TERM, modeled without signaling any real PID (before prints UNSAFE KILL; after refuses escalation):

```bash
require_run; mkdir -p "$RUN_DIR"; printf '777777 123\n' >"$RUN_DIR/web.pid"
saved=$(declare -f pid_alive group_alive owns_process_group)
pid_alive() { return 0; }; group_alive() { return 0; }; sleep() { :; }
owns_process_group() { [[ ! -f $probe/terminated ]]; }
kill() { [[ $1 != -TERM ]] || touch "$probe/terminated"; [[ $1 != -KILL ]] || echo 'UNSAFE KILL'; return 0; }
stop_group web || true
rm -f "$RUN_DIR/web.pid"
unset -f kill sleep; eval "$saved"
```

## Offline driver reproduction

This mock checks only selector/metadata logic, not real app rendering. Run the code below as `node - MODE COMMAND HINT <<'JS'` with the fenced JavaScript as stdin. MODE is `before` or `after`; before reconstructs only the original selector/key parsing expression without modifying files.

Exact invocations and observations:

- `node - before send`: fails to find hardcoded Message…; `after send`: composer present.
- `node - before state`: reports composer absent; `after state`: composer present.
- `node - after send 'Ask about weather, or request a file deletion…'`: Conversation composer present.
- `node - before keyless keyed-last`: accepts incorrectly; `after keyless keyed-last`: rejects.
- `node - before keyless keyless-last`: rejects incorrectly; `after keyless keyless-last`: accepts.

```javascript
const fs = require('node:fs');
const vm = require('node:vm');
const mode = process.argv[2] || 'after';
const command = process.argv[3] || 'send';
const hint = process.argv[4] || 'Ask about weather or math…';
let source = fs.readFileSync('.cursor/skills/verify-flutter-chat/scripts/drive.cjs', 'utf8');
if (mode === 'before') source = source.replace(/const L = \{ \.\.\.LABELS\[flags\.lang \|\| 'en'\].*?;/, "const L = LABELS[flags.lang || 'en'];");
if (mode === 'before') source = source.replace(/const keys = \[\.\.\.fs\.readFileSync.*?;/, "const keys = (/^KEYS_BAKED=(.*)$/m.exec(fs.readFileSync(path.join(RUN_DIR, 'state.env'), 'utf8')) || [])[1] || ''; ");
source = source.replace(/main\(\)\.then\([\s\S]*$/, 'globalThis.probeMain = main;');
source += '\nglobalThis.probeKeyless = requireKeylessBuild;';
let value = '';
let observed;
const locator = (present, textbox = false) => ({
  waitFor: async () => {}, count: async () => present ? 1 : 0,
  click: async () => { if (!present) throw Error('No textbox with hardcoded hint Message…'); },
  press: async () => { value = ''; }, pressSequentially: async text => { value = text; },
  inputValue: async () => value, isEditable: async () => present && textbox,
  isEnabled: async () => present, ariaSnapshot: async () => '',
});
const page = {
  url: () => 'http://127.0.0.1:12345/', on: () => {},
  locator: () => locator(true), waitForTimeout: async () => {},
  getByRole: (role, { name }) => locator(role === 'textbox' ? name === hint : role === 'button' && name === 'Send message', role === 'textbox'),
};
const context = { pages: () => [page] };
const mockRequire = name => name === 'playwright' ? { chromium: { connectOverCDP: async () => ({ contexts: () => [context] }) } }
  : name === 'node:fs' ? { ...fs, readFileSync: () => hint === 'keyed-last' ? 'KEYS_BAKED=\nKEYS_BAKED=openai\n' : 'KEYS_BAKED=openai\nKEYS_BAKED=\n' } : require(name);
mockRequire.resolve = name => name;
const sandbox = {
  require: mockRequire,
  process: { env: { VFC_WEB_PORT: '12345', VFC_CDP_PORT: '12346', VFC_EVIDENCE_DIR: '/tmp', VFC_RUN_DIR: '/tmp/codex-offline-probe', VFC_APP: 'advanced_app' }, execPath: process.execPath, cwd: () => process.cwd(),
    argv: ['node', 'drive.cjs', command, ...(command === 'send' ? ['hello'] : []), '--hint', hint] },
  console: { ...console, log: text => { console.log(text); try { observed = JSON.parse(text); } catch {} } }, URL, setTimeout, clearTimeout,
};
vm.createContext(sandbox);
vm.runInContext(source, sandbox);
if (command === 'keyless') {
  try { sandbox.probeKeyless(); console.log('ACCEPT keyless guard'); }
  catch (error) { console.log(`REJECT ${error.message}`); }
  process.exit();
}
sandbox.probeMain().then(() => {
  if (!observed?.composerPresent) { console.log('FAIL custom composer reported absent'); process.exitCode = 1; }
  else console.log('PASS custom-hint command');
}, error => { console.log(`FAIL ${error.message}`); process.exitCode = 1; });
```

## Additional checks and remaining limits

- Mismatched `VFC_APP` rejects build/env; `down` deliberately ignores the selector and incomplete state so cleanup cannot be blocked.
- Empty-state cleanup removes scratch and preserves evidence.
- Two owned advanced_app Chromium/web instances ran simultaneously on separate ports. Cleaning the first left the second's processes and evidence intact, then the second was cleaned.
- Synthetic isolated source-tree probes confirmed that selected-app/package/package-config changes alter the fingerprint; other-app changes do not. A suspected binary-file hole was disproved: Git's diff already includes content hashes.
- `bash -n scripts/vfc` and `node --check scripts/drive.cjs` passed.
- No new real Flutter build was run during this review; provider/live paths and native mobile behavior remain unverified. New advanced-app scenarios beyond the prior worker's dark-gallery run were inspected, not rerun against a real build.
