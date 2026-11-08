"""Writes test/prompt_drift.dart: how the reference's checked-in prompts differ
from what its own source at the pinned commit generates.

Usage: python3 -I tool/prompt_drift.py <ours-chat.txt> <ours-dashboard.txt>
Run from the package directory after writing our prompts to those files.
Every difference must be a replaced or inserted line; a deleted line is an error.
"""
import difflib, sys

def lit(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"

repl, inserts = {}, []
pairs = [(sys.argv[1], 'test/fixtures/system-prompt.txt'), (sys.argv[2], 'test/fixtures/dashboard-system-prompt.txt')]
for ours, gold in pairs:
    a, b = open(gold).read().split('\n'), open(ours).read().split('\n')
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == 'replace':
            assert i2 - i1 == j2 - j1, (gold, i1)
            repl.update(zip(a[i1:i2], b[j1:j2]))
        elif op == 'insert':
            item = (a[i1 - 1], tuple(b[j1:j2]))
            if item not in inserts:
                inserts.append(item)
        elif op == 'delete':
            raise SystemExit(f'{gold}: unexpected deleted lines {i1}-{i2}')
out = [
    "// The reference's checked-in prompts (src/generated/*system-prompt.txt) predate",
    "// its own source at the pinned commit: spec.json and prompt-options.ts from the",
    "// same commit have newer text. These are the only allowed differences, each",
    "// taken from that newer source. Regenerate with tool/prompt_drift.py.",
    "",
    "/// Stale golden line -> the line the current source produces.",
    "const promptLineUpdates = <String, String>{",
]
for x, y in repl.items():
    out += [f"  {lit(x)}:", f"      {lit(y)},"]
out += ["};", "", "/// Lines the current source adds, after the golden line they follow.",
        "const promptLineInserts = <(String, List<String>)>["]
for after, ins in inserts:
    out += [f"  ({lit(after)}, ["] + [f"    {lit(l)}," for l in ins] + ["  ]),"]
out += ["];", ""]
open('test/prompt_drift.dart', 'w').write('\n'.join(out))
print(len(repl), 'updates,', len(inserts), 'insert groups')
