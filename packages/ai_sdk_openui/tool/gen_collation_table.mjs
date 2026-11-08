// Usage (Node 26; the data must match Node's Unicode and CLDR versions):
//   curl -sSfLO https://raw.githubusercontent.com/unicode-org/cldr/release-48/common/uca/allkeys_CLDR.txt
//   curl -sSfLO https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt
//   node tool/gen_collation_table.mjs allkeys_CLDR.txt UnicodeData.txt > lib/src/runtime/collation_table.dart
// Packs ICU's root collation (CLDR allkeys, with Han in ICU's radical-stroke
// order read from Node), canonical decompositions and combining classes, so
// @Sort orders text as String.prototype.localeCompare does. Rerun after a
// Node upgrade with the files for node -p process.versions.unicode and .cldr.
import { readFileSync } from "node:fs";

const keys = readFileSync(process.argv[2], "utf8");
const unicodeData = readFileSync(process.argv[3], "utf8");
const version = /^@version (\S+)/m.exec(keys)[1];

const ccc = new Map();
for (const line of unicodeData.split("\n")) {
  const f = line.split(";");
  if (f.length > 3 && f[3] !== "0") ccc.set(parseInt(f[0], 16), Number(f[3]));
}

const isHangul = (cp) => cp >= 0xac00 && cp <= 0xd7a3;
const decompositions = new Map();
for (let cp = 0; cp <= 0x10ffff; cp++) {
  if ((cp >= 0xd800 && cp <= 0xdfff) || isHangul(cp)) continue;
  const s = String.fromCodePoint(cp);
  const d = s.normalize("NFD");
  if (d !== s) decompositions.set(cp, [...d].map((c) => c.codePointAt(0)));
}
const normal = (cp) => !decompositions.has(cp) && !isHangul(cp);

// ICU orders Han by radical and stroke count, not by code point: take the order from Node.
const ideograph = /\p{Unified_Ideograph}/u;
const han = [];
for (let cp = 0; cp <= 0x10ffff; cp++) {
  if (!(cp >= 0xd800 && cp <= 0xdfff) && ideograph.test(String.fromCodePoint(cp))) han.push(cp);
}
const collator = new Intl.Collator("en");
han.sort((a, b) => collator.compare(String.fromCodePoint(a), String.fromCodePoint(b)) || a - b);
const hanRank = new Map(han.map((cp, i) => [cp, i]));

const singles = new Map();
const contractions = [];
for (const line of keys.split("\n")) {
  const body = line.split("#")[0].trim();
  if (!body || body.startsWith("@")) continue;
  const [key, rest] = body.split(";");
  const cps = key.trim().split(/\s+/).map((h) => parseInt(h, 16));
  if (!cps.every(normal)) continue;
  const ces = [...rest.matchAll(/\[[.*]([0-9A-F]{4})\.([0-9A-F]{4})\.([0-9A-F]{4})\]/g)].map(
    ([, p, s, t]) => [parseInt(p, 16), parseInt(s, 16), parseInt(t, 16)],
  );
  // A Han implicit pair (radicals, compatibility forms) takes the Han character's ICU rank.
  for (let i = 0; i + 1 < ces.length; i++) {
    const lead = ces[i][0];
    if (lead < 0xfb40 || lead > 0xfbbf) continue;
    const cp = ((lead - (lead < 0xfb80 ? 0xfb40 : 0xfb80)) << 15) | (ces[i + 1][0] & 0x7fff);
    const rank = hanRank.get(cp);
    if (rank === undefined) throw new Error(`no Han rank for ${cp.toString(16)}`);
    ces[i][0] = 0xfb40 + (rank >> 15);
    ces[i + 1][0] = (rank & 0x7fff) | 0x8000;
  }
  if (cps.length === 1) singles.set(cps[0], ces);
  else contractions.push([cps, ces]);
}

const bytes = [];
const varint = (n) => {
  while (n >= 0x80) {
    bytes.push((n % 128) | 0x80);
    n = Math.floor(n / 128);
  }
  bytes.push(n);
};
const zigzag = (n) => (n < 0 ? -2 * n - 1 : 2 * n);
let lastP = 0;
const ce = ([p, s, t]) => {
  varint(zigzag(p - lastP));
  lastP = p;
  varint(s * 32 + t);
};
const counts = [];

// 1. Single code points: [gap, (run length - 1) * 32 + CE count, CEs]. A run is consecutive
//    code points with one CE each, primaries rising by one, the same secondary and tertiary.
let records = 0;
let end = 0;
const cps = [...singles.keys()].sort((a, b) => a - b);
for (let i = 0; i < cps.length; ) {
  const cp = cps[i];
  const ces = singles.get(cp);
  let run = 1;
  while (ces.length === 1 && i + run < cps.length && cps[i + run] === cp + run) {
    const [next] = singles.get(cp + run);
    if (singles.get(cp + run).length !== 1 || next[0] !== ces[0][0] + run || next[1] !== ces[0][1] || next[2] !== ces[0][2]) break;
    run++;
  }
  varint(cp - end);
  varint((run - 1) * 32 + ces.length);
  ces.forEach(ce);
  end = cp + run;
  i += run;
  records++;
}
counts.push(records);

// 2. Contractions: [length, code points, CE count, CEs].
for (const [seq, ces] of contractions) {
  varint(seq.length);
  seq.forEach(varint);
  varint(ces.length);
  ces.forEach(ce);
}
counts.push(contractions.length);

// 3. Canonical decompositions: [gap from the previous code point, length, code points].
let prev = 0;
for (const [cp, seq] of [...decompositions].sort((a, b) => a[0] - b[0])) {
  varint(cp - prev);
  prev = cp;
  varint(seq.length);
  seq.forEach(varint);
}
counts.push(decompositions.size);

// 4. Combining classes: runs of [gap, length, class].
records = 0;
end = 0;
const marks = [...ccc.keys()].sort((a, b) => a - b);
for (let i = 0; i < marks.length; ) {
  let run = 1;
  while (i + run < marks.length && marks[i + run] === marks[i] + run && ccc.get(marks[i + run]) === ccc.get(marks[i])) run++;
  varint(marks[i] - end);
  varint(run);
  varint(ccc.get(marks[i]));
  end = marks[i] + run;
  i += run;
  records++;
}
counts.push(records);

// 5. Han in ICU order: runs of consecutive code points, [signed gap from the previous run's end, length].
records = 0;
end = 0;
for (let i = 0; i < han.length; ) {
  let run = 1;
  while (i + run < han.length && han[i + run] === han[i] + run) run++;
  varint(zigzag(han[i] - end));
  varint(run);
  end = han[i] + run;
  i += run;
  records++;
}
counts.push(records);

// UCA 17 implicit weights for scripts without table entries, over their assigned code points:
// [first, last, lead primary, code point the second primary counts from].
const implicitScripts = [
  [0x17000, 0x187ff, 0xfb00, 0x17000], // Tangut
  [0x18800, 0x18aff, 0xfb01, 0x18800], // Tangut Components
  [0x18d00, 0x18d7f, 0xfb00, 0x17000], // Tangut Supplement
  [0x18d80, 0x18dff, 0xfb01, 0x18800], // Tangut Components Supplement
  [0x1b170, 0x1b2ff, 0xfb02, 0x1b170], // Nushu
  [0x18b00, 0x18cff, 0xfb03, 0x18b00], // Khitan Small Script
];
const assigned = /\p{Assigned}/u;
const implicit = [];
for (const [lo, hi, lead, base] of implicitScripts) {
  for (let cp = lo; cp <= hi; cp++) {
    if (!assigned.test(String.fromCodePoint(cp))) continue;
    const last = implicit[implicit.length - 1];
    if (last && last[1] === cp - 1 && last[2] === lead) last[1] = cp;
    else implicit.push([cp, cp, lead, base]);
  }
}

const data = Buffer.from(bytes).toString("base64");
const lines = data.match(/.{1,76}/g).map((c) => `    '${c}'`).join("\n");
process.stdout.write(`// Generated by tool/gen_collation_table.mjs from allkeys_CLDR.txt ${version} and
// UnicodeData.txt with Node ${process.version} (ICU ${process.versions.icu}, CLDR ${process.versions.cldr}); do not edit.

/// Record counts of the five sections of [collationData]: code points,
/// contractions, decompositions, combining class runs and Han runs.
const collationCounts = <int>[${counts.join(", ")}];

/// Assigned code points with UCA implicit weights of their own script:
/// first, last, lead primary, and the code point the second primary counts from.
const collationImplicitScripts = <int>[
${implicit.flat().map((n) => "  0x" + n.toString(16).toUpperCase() + ",").join("\n")}
];

/// Varint records, as tool/gen_collation_table.mjs writes them.
const collationData =
${lines};
`);
